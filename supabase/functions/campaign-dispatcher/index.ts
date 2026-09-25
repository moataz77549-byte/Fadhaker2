// ============================================================================
// supabase/functions/campaign-dispatcher/index.ts
//
// Scheduled dispatcher for due notification campaigns (invoked by pg_cron).
//
// Picks up app.notification_campaigns rows where
//   status = 'scheduled' AND scheduled_at <= now()
// claims each one (status → 'processing'), then dispatches through the SAME
// FCM HTTP v1 path as the `notifications` function:
//
//   * Google service-account credentials are read ONLY from Supabase Secrets
//     at runtime (FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL /
//     FIREBASE_PRIVATE_KEY) — never written in code, never logged, never
//     returned. Only the secret NAMES appear here.
//   * Target installations come from app.installations
//     (notifications_enabled = true, revoked_at IS NULL).
//   * Every device delivery is recorded in app.notification_deliveries.
//   * The campaign ends as status='sent' (+ sent_at) or status='failed'
//     (+ last_error). Partial failures still mark the campaign 'sent' when at
//     least one device received it — matching `notifications` semantics —
//     with sent_count / failed_count filled in honestly.
//
// Authorization: the caller must present either
//   (a) the service_role key (pg_cron path), or
//   (b) a valid admin JWT whose owner holds `notifications.write`
//       (manual trigger path).
// ============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-campaign-dispatcher-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---- FCM helpers (same path as the `notifications` function) ---------------

const NOTIFICATION_TYPES = new Set([
  'announcement',
  'urgent',
  'live_broadcast',
  'featured_recitation',
  'reminder',
]);

function isHighPriority(type: string): boolean {
  return type === 'urgent' || type === 'live_broadcast';
}

function base64UrlEncode(bytes: Uint8Array): string {
  let base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

/**
 * Google OAuth2 access token for FCM HTTP v1 (Web Crypto RSA-SHA256).
 * Secrets are read from Supabase Secrets at runtime — never persisted.
 */
async function getFcmAccessToken(clientEmail: string, privateKeyRaw: string): Promise<string> {
  const formattedKey = privateKeyRaw.replace(/\\n/g, '\n');
  const pemContents = formattedKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  const binaryDerString = atob(pemContents);
  const derBuffer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    derBuffer[i] = binaryDerString.charCodeAt(i);
  }

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    derBuffer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const now = Math.floor(Date.now() / 1000);
  const unsignedToken =
    `${base64UrlEncode(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))}.` +
    `${base64UrlEncode(new TextEncoder().encode(JSON.stringify({
      iss: clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      exp: now + 3600,
      iat: now,
    })))}`;

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken),
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const tokenData = await tokenResponse.json();
  if (!tokenResponse.ok) {
    throw new Error(`Google OAuth error: ${tokenData.error_description || tokenData.error}`);
  }
  return tokenData.access_token;
}

interface SendResult { success: boolean; messageId?: string; error?: string; }

async function sendFcmV1Message(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  targetRoute: string,
  notificationType: string,
  deliveryId: string,
): Promise<SendResult> {
  const highPriority = isHighPriority(notificationType);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data: {
          title,
          body,
          targetRoute,
          notification_type: notificationType,
          delivery_id: deliveryId,
        },
        android: {
          priority: highPriority ? 'HIGH' : 'NORMAL',
          notification: { channel_id: 'fadhkur_fcm_channel', sound: 'default' },
        },
        apns: {
          headers: highPriority ? { 'apns-priority': '10' } : {},
          payload: { aps: { alert: { title, body }, sound: 'default' } },
        },
      },
    }),
  });

  if (res.ok) {
    const okJson = await res.json().catch(() => ({}));
    return { success: true, messageId: okJson?.name ?? null };
  }
  const errorJson = await res.json().catch(() => ({}));
  return { success: false, error: JSON.stringify(errorJson).slice(0, 2000) };
}

// ---- Authorization ----------------------------------------------------------

/** Manual-trigger path: active administrator holding notifications.write. */
async function authorizeNotificationAdmin(adminClient: any, userId: string): Promise<boolean> {
  const { data: admin, error: adminError } = await adminClient
    .schema('app')
    .from('administrators')
    .select('id, is_active, deleted_at')
    .eq('id', userId)
    .maybeSingle();
  if (adminError || !admin || !admin.is_active || admin.deleted_at) return false;

  const { data: grants, error: grantError } = await adminClient
    .schema('app')
    .from('administrator_roles')
    .select('roles!inner(code, role_permissions!inner(permissions!inner(code)))')
    .eq('administrator_id', userId);
  if (grantError || !grants) return false;

  const codes = new Set<string>();
  for (const g of grants as any[]) {
    codes.add(g.roles.code);
    for (const rp of g.roles.role_permissions ?? []) {
      codes.add(rp.permissions.code);
    }
  }
  return codes.has('SUPER_ADMIN') || codes.has('notifications.write');
}

// ---- Dispatch of a single claimed campaign -----------------------------------

interface Campaign {
  id: string;
  title: string;
  body: string;
  notification_type: string;
  target_type: string;
  target: any;
  payload: any;
  deep_link: string | null;
}

async function dispatchCampaign(
  adminClient: any,
  campaign: Campaign,
  fcm: { projectId: string; clientEmail: string; privateKey: string } | null,
): Promise<{ status: string; successCount: number; failureCount: number; lastError: string | null }> {
  const deliveryId = crypto.randomUUID();
  const type = NOTIFICATION_TYPES.has(campaign.notification_type)
    ? campaign.notification_type
    : 'announcement';
  const deepLink =
    typeof campaign.deep_link === 'string' && campaign.deep_link.startsWith('/')
      ? campaign.deep_link
      : '/home';

  const fail = async (msg: string) => {
    await adminClient.schema('app').from('notification_campaigns').update({
      status: 'failed',
      sent_at: new Date().toISOString(),
      last_error: msg.slice(0, 2000),
    }).eq('id', campaign.id);
    return { status: 'failed', successCount: 0, failureCount: 0, lastError: msg };
  };

  // Resolve target installations (consent + not revoked).
  let query = adminClient
    .schema('app')
    .from('installations')
    .select('id, firebase_token_encrypted')
    .eq('notifications_enabled', true)
    .is('revoked_at', null);

  const target = campaign.target ?? {};
  if (campaign.target_type === 'device' && target.testInstallationId) {
    query = query.eq('id', target.testInstallationId);
  }

  const { data: installations, error: dbError } = await query;
  if (dbError) {
    return fail(`Target resolution failed: ${dbError.message}`);
  }

  const targets: { id: string; token: string }[] = [];
  for (const inst of installations ?? []) {
    if (inst.firebase_token_encrypted) {
      targets.push({ id: inst.id, token: inst.firebase_token_encrypted });
    }
  }

  if (!fcm) {
    // FCM secrets not configured: do not fake a send; mark honestly.
    return fail('FCM_NOT_CONFIGURED: FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY secrets are missing');
  }

  if (targets.length === 0) {
    await adminClient.schema('app').from('notification_campaigns').update({
      status: 'sent',
      sent_at: new Date().toISOString(),
      sent_count: 0,
      failed_count: 0,
      last_error: 'No eligible installations at dispatch time',
    }).eq('id', campaign.id);
    return { status: 'sent', successCount: 0, failureCount: 0, lastError: 'No eligible installations' };
  }

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(fcm.clientEmail, fcm.privateKey);
  } catch (e: any) {
    return fail(`FCM_AUTH_FAILED: ${e?.message || String(e)}`);
  }

  let successCount = 0;
  let failureCount = 0;
  let firstError: string | null = null;
  const deliveryRows: any[] = [];

  for (const target of targets) {
    let result: SendResult;
    try {
      result = await sendFcmV1Message(
        fcm.projectId, accessToken, target.token,
        campaign.title, campaign.body, deepLink, type, deliveryId,
      );
    } catch (e: any) {
      result = { success: false, error: `transport: ${e?.message || String(e)}`.slice(0, 500) };
    }
    if (result.success) {
      successCount++;
      deliveryRows.push({
        campaign_id: campaign.id, installation_id: target.id,
        status: 'sent', firebase_message_id: result.messageId, sent_at: new Date().toISOString(),
      });
    } else {
      failureCount++;
      if (!firstError) firstError = result.error ?? 'unknown error';
      deliveryRows.push({
        campaign_id: campaign.id, installation_id: target.id,
        status: 'failed', error_message: result.error,
      });
    }
  }

  if (deliveryRows.length > 0) {
    await adminClient.schema('app').from('notification_deliveries').insert(deliveryRows);
  }

  const finalStatus = successCount === 0 ? 'failed' : 'sent';
  await adminClient.schema('app').from('notification_campaigns').update({
    status: finalStatus,
    sent_at: new Date().toISOString(),
    sent_count: successCount,
    failed_count: failureCount,
    last_error: firstError,
  }).eq('id', campaign.id);

  await adminClient.schema('app').rpc('create_audit_event', {
    p_action: 'NOTIFICATION_CRON_DISPATCH',
    p_resource_type: 'app.notification_campaigns',
    p_resource_id: String(campaign.id),
    p_request_id: deliveryId,
    p_metadata: { title: campaign.title, targetType: campaign.target_type, successCount, failureCount },
  });

  return { status: finalStatus, successCount, failureCount, lastError: firstError };
}

// ---- HTTP entrypoint ---------------------------------------------------------

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const json = (payload: unknown, status = 200) =>
    new Response(JSON.stringify(payload), {
      status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  // Firebase service-account fields — Supabase Secrets, runtime only.
  // Only the secret NAMES appear in code; values are never logged or returned.
  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
  const firebaseClientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL') ?? '';
  const firebasePrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY') ?? '';

  if (!supabaseUrl || !supabaseServiceKey) {
    return json({ error: 'Service role key unconfigured' }, 500);
  }
  const adminClient = createClient(supabaseUrl, supabaseServiceKey);

  // ---- 1. Authorize: cron secret, service_role bearer, or admin JWT --------
  const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const suppliedCronSecret = req.headers.get('x-campaign-dispatcher-secret') || '';
  let authorized = bearer === supabaseServiceKey;

  if (!authorized && suppliedCronSecret) {
    const { data: expectedSecret, error: secretError } = await adminClient.rpc('get_cron_secret', {
      p_name: 'campaign-dispatcher',
    });
    authorized = !secretError && typeof expectedSecret === 'string' &&
      expectedSecret.length >= 32 && suppliedCronSecret === expectedSecret;
  }

  if (!authorized && bearer) {
    const { data: { user }, error: authError } = await adminClient.auth.getUser(bearer);
    if (!authError && user && await authorizeNotificationAdmin(adminClient, user.id)) {
      authorized = true;
    }
  }
  if (!authorized) return json({ error: 'Forbidden' }, 403);

  // ---- 2. Claim due campaigns (status='scheduled', scheduled_at <= now()) ---
  const { data: due, error: dueError } = await adminClient
    .schema('app')
    .from('notification_campaigns')
    .select('id, title, body, notification_type, target_type, target, payload, deep_link')
    .eq('status', 'scheduled')
    .lte('scheduled_at', new Date().toISOString())
    .order('scheduled_at', { ascending: true })
    .limit(10);

  if (dueError) {
    return json({ error: 'Failed to query due campaigns', details: dueError.message }, 500);
  }

  const fcm = (firebaseProjectId && firebaseClientEmail && firebasePrivateKey)
    ? { projectId: firebaseProjectId, clientEmail: firebaseClientEmail, privateKey: firebasePrivateKey }
    : null;

  const results: any[] = [];
  for (const campaign of (due ?? []) as Campaign[]) {
    // Claim: prevents a concurrent dispatcher run from double-sending.
    const { error: claimError } = await adminClient
      .schema('app')
      .from('notification_campaigns')
      .update({ status: 'processing' })
      .eq('id', campaign.id)
      .eq('status', 'scheduled');
    if (claimError) {
      results.push({ campaign_id: campaign.id, status: 'claim_failed', error: claimError.message });
      continue;
    }
    const outcome = await dispatchCampaign(adminClient, campaign, fcm);
    results.push({ campaign_id: campaign.id, ...outcome });
  }

  return json({
    success: true,
    processed: results.length,
    results,
    fcmConfigured: fcm !== null,
    checkedAt: new Date().toISOString(),
  });
});
