// ============================================================================
// supabase/functions/notifications/index.ts
//
// Admin-only notification dispatch for Fadhkur.
//
//  * Called by administrators/backend only — NEVER from the Flutter client.
//    The Flutter app registers/revokes its installation via
//    `quran-yutla-api/notifications/{register,revoke}` with the publishable key;
//    it never sends broadcasts.
//  * Authorization: the caller Bearer JWT must belong to an ACTIVE
//    administrator (app.administrators) holding the `notifications.write`
//    permission (or the SUPER_ADMIN role). Verified server-side on every call.
//  * Campaigns are persisted in app.notification_campaigns (status lifecycle:
//    draft → scheduled → processing → completed|failed|cancelled) and every
//    device delivery in app.notification_deliveries — before/after sending.
//  * FCM is sent via the HTTP v1 API using a Google service account whose
//    credentials are read ONLY from Supabase Secrets at runtime
//    (FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY).
//    They are never written in code, never logged, never returned.
//  * Scheduling: a future `scheduled_at` stores the campaign as `scheduled`
//    and returns 202 without dispatching (a scheduler/cron picks it up later).
//  * Notification kinds: announcement | urgent | live_broadcast |
//    featured_recitation | reminder. Urgent/live use HIGH priority.
//  * Deep links are allow-listed to in-app routes only (open-redirect defense).
// ============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Strict allow-list of client navigation routes (deep-link validation).
const ALLOWED_ROUTES = new Set([
  '/',
  '/home',
  '/radio',
  '/reciters',
  '/quran',
  '/library',
  '/adhkar',
  '/prayer-times',
  '/custom-reminders',
  '/settings',
]);

const SURAH_ROUTE_RE = /^\/quran\/surah\/([1-9]|[1-9][0-9]|10[0-9]|11[0-4])$/;

function sanitizeRoute(route?: string): string {
  if (!route) return '/home';
  if (ALLOWED_ROUTES.has(route)) return route;
  if (SURAH_ROUTE_RE.test(route)) return route;
  return '/home';
}

// notification_type → dispatch behavior
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
 * privateKeyRaw is read from Supabase Secrets at runtime — never persisted.
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
          ...(notificationType === 'live_broadcast' ? { is_live: 'true' } : {}),
        },
        android: {
          // Urgent / live broadcasts wake the device immediately.
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

/**
 * Server-side admin authorization.
 * The caller must be an ACTIVE administrator holding `notifications.write`
 * (or the SUPER_ADMIN role). Roles live in app.roles (UPPER_SNAKE_CASE codes).
 */
async function authorizeNotificationAdmin(adminClient: any, userId: string): Promise<boolean> {
  const { data: admin, error: adminError } = await adminClient
    .schema('app')
    .from('administrators')
    .select('id, user_id, is_active, deleted_at')
    .or(`id.eq.${userId},user_id.eq.${userId}`)
    .maybeSingle();
  if (adminError || !admin || !admin.is_active || admin.deleted_at) return false;

  const { data: grants, error: grantError } = await adminClient
    .schema('app')
    .from('administrator_roles')
    .select('roles!inner(code, role_permissions!inner(permissions!inner(code)))')
    .eq('administrator_id', admin.id);
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
  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
  const firebaseClientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL') ?? '';
  const firebasePrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY') ?? '';

  if (!supabaseUrl || !supabaseServiceKey) {
    return json({ error: 'Service role key unconfigured' }, 500);
  }
  const adminClient = createClient(supabaseUrl, supabaseServiceKey);

  // ---- 1. Authenticate + authorize (admin only) ----
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'Unauthorized: admin JWT required' }, 401);

  const { data: { user }, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !user) {
    return json({ error: 'Unauthorized: invalid admin JWT' }, 401);
  }
  if (!(await authorizeNotificationAdmin(adminClient, user.id))) {
    return json({ error: 'Forbidden: notifications.write permission required' }, 403);
  }

  // ---- 2. Parse + validate request ----
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const {
    title,
    body: messageBody,
    targetRoute = '/home',
    targetType = 'all', // 'all' | 'device' | 'test' (+ legacy aliases below)
    notification_type = 'announcement',
    scheduled_at = null,
    testInstallationId = null,
    fcmTokenDirect = null,
    data: extraData = {},
  } = body ?? {};

  if (!title || !messageBody) {
    return json({ error: 'title and body are required' }, 400);
  }
  const type = NOTIFICATION_TYPES.has(notification_type) ? notification_type : 'announcement';
  const deepLink = sanitizeRoute(targetRoute);
  const deliveryId = crypto.randomUUID();

  // Legacy aliases accepted by older admin clients.
  const normalizedTarget =
    targetType === 'sendTest' || targetType === 'sendToInstallation' || targetType === 'sendToDevice'
      ? 'device'
      : targetType === 'sendBroadcast' || targetType === 'sendToSegment'
        ? 'all'
        : targetType;
  if (!['all', 'device', 'test'].includes(normalizedTarget)) {
    return json({ error: "targetType must be 'all', 'device' or 'test'" }, 400);
  }

  // ---- 3. Persist the campaign first (audit trail before any dispatch) ----
  const scheduledAt = scheduled_at ? new Date(scheduled_at) : null;
  if (scheduledAt && isNaN(scheduledAt.getTime())) {
    return json({ error: 'scheduled_at must be a valid ISO timestamp' }, 400);
  }
  const isFuture = scheduledAt !== null && scheduledAt.getTime() > Date.now() + 60_000;

  const { data: campaign, error: campaignError } = await adminClient
    .schema('app')
    .from('notification_campaigns')
    .insert({
      title,
      body: messageBody,
      notification_type: type,
      target_type: normalizedTarget === 'all' ? 'all' : 'device',
      target: { targetType: normalizedTarget, testInstallationId },
      payload: { targetRoute: deepLink, notification_type: type, ...(extraData ?? {}) },
      deep_link: deepLink,
      scheduled_at: scheduledAt ? scheduledAt.toISOString() : new Date().toISOString(),
      status: isFuture ? 'scheduled' : 'processing',
      created_by: user.id,
    })
    .select('id')
    .single();

  if (campaignError || !campaign) {
    return json({ error: 'Failed to persist campaign', details: campaignError?.message }, 500);
  }
  const campaignId = campaign.id;

  // ---- 4. Scheduled for later → store only, do not dispatch ----
  if (isFuture) {
    await adminClient.schema('app').rpc('create_audit_event', {
      p_action: 'NOTIFICATION_SCHEDULED',
      p_resource_type: 'app.notification_campaigns',
      p_resource_id: String(campaignId),
      p_request_id: deliveryId,
      p_metadata: { title, targetType: normalizedTarget, targetRoute: deepLink, scheduled_at: scheduledAt!.toISOString() },
    });
    return json({
      success: true,
      campaign_id: campaignId,
      status: 'scheduled',
      scheduled_at: scheduledAt!.toISOString(),
      deliveryId,
    }, 202);
  }

  // ---- 5. Resolve target installations (consent + not revoked) ----
  let query = adminClient
    .schema('app')
    .from('installations')
    .select('id, platform, firebase_token_encrypted, notifications_enabled')
    .eq('notifications_enabled', true)
    .is('revoked_at', null);

  if ((normalizedTarget === 'device' || normalizedTarget === 'test') && testInstallationId) {
    query = query.eq('id', testInstallationId);
  }

  const { data: installations, error: dbError } = await query;
  if (dbError) {
    await adminClient.schema('app').from('notification_campaigns').update({
      status: 'failed', last_error: `Target resolution failed: ${dbError.message}`,
    }).eq('id', campaignId);
    return json({ error: dbError.message }, 500);
  }

  const targets: { id: string; token: string }[] = [];
  if (fcmTokenDirect) {
    // Direct-token path is for admin testing only; never logged in clear.
    targets.push({ id: testInstallationId || 'direct', token: fcmTokenDirect });
  } else {
    for (const inst of installations ?? []) {
      if (inst.firebase_token_encrypted) {
        targets.push({ id: inst.id, token: inst.firebase_token_encrypted });
      }
    }
  }

  // ---- 6. Dispatch via FCM HTTP v1 (service account from Secrets) ----
  const isFcmConfigured = Boolean(firebaseProjectId && firebaseClientEmail && firebasePrivateKey);
  let successCount = 0;
  let failureCount = 0;
  let firstError: string | null = null;
  const deliveryRows: any[] = [];

  if (isFcmConfigured && targets.length > 0) {
    let accessToken: string;
    try {
      accessToken = await getFcmAccessToken(firebaseClientEmail, firebasePrivateKey);
    } catch (e: any) {
      const msg = `FCM_AUTH_FAILED: ${e?.message || String(e)}`;
      await adminClient.schema('app').from('notification_campaigns').update({
        status: 'failed', last_error: msg, sent_at: new Date().toISOString(),
      }).eq('id', campaignId);
      return json({ error: 'FCM_DISPATCH_FAILED', details: 'OAuth token exchange failed' }, 500);
    }

    for (const target of targets) {
      let result: SendResult;
      try {
        result = await sendFcmV1Message(
          firebaseProjectId, accessToken, target.token,
          title, messageBody, deepLink, type, deliveryId,
        );
      } catch (e: any) {
        result = { success: false, error: `transport: ${e?.message || String(e)}`.slice(0, 500) };
      }
      if (result.success) {
        successCount++;
        deliveryRows.push({
          campaign_id: campaignId, installation_id: target.id,
          status: 'sent', firebase_message_id: result.messageId, sent_at: new Date().toISOString(),
        });
      } else {
        failureCount++;
        if (!firstError) firstError = result.error ?? 'unknown error';
        deliveryRows.push({
          campaign_id: campaignId, installation_id: target.id,
          status: 'failed', error_message: result.error,
        });
      }
    }
  }

  if (deliveryRows.length > 0) {
    // Best-effort batch insert; dispatch already happened.
    await adminClient.schema('app').from('notification_deliveries').insert(deliveryRows);
  }

  const finalStatus =
    targets.length === 0 ? 'completed'
      : failureCount === 0 ? 'completed'
        : successCount === 0 ? 'failed'
          : 'completed';

  await adminClient.schema('app').from('notification_campaigns').update({
    status: finalStatus,
    sent_at: new Date().toISOString(),
    sent_count: successCount,
    failed_count: failureCount,
    last_error: firstError,
  }).eq('id', campaignId);

  // ---- 7. Audit trail (never log raw FCM tokens or private keys) ----
  await adminClient.schema('app').rpc('create_audit_event', {
    p_action: normalizedTarget === 'test' ? 'NOTIFICATION_TEST_SEND' : 'NOTIFICATION_DISPATCH',
    p_resource_type: 'app.notification_campaigns',
    p_resource_id: String(campaignId),
    p_request_id: deliveryId,
    p_metadata: {
      title,
      targetType: normalizedTarget,
      targetRoute: deepLink,
      notification_type: type,
      targetedRecipients: targets.length,
      successCount,
      failureCount,
    },
  });

  return json({
    success: true,
    campaign_id: campaignId,
    status: finalStatus,
    notification_type: type,
    targetedRecipients: targets.length,
    successCount,
    failureCount,
    last_error: firstError,
    fcmConfigured: isFcmConfigured,
    mode: isFcmConfigured ? 'FCM_V1_LIVE' : 'DRY_RUN_ACCEPTED',
    deliveryId,
    dispatchedAt: new Date().toISOString(),
  });
});
