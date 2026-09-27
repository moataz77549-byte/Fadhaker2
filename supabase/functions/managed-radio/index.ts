import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseServiceKey) {
    return new Response(JSON.stringify({ error: 'Service role key unconfigured' }), { status: 500 });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // Return currently active playing radio stream and queue state.
  // Honest contract: reflects the radio.now_playing row as-is; no fabricated
  // titles and no hardcoded engine claims. Absent row => null (client shows
  // its own empty state), never fake "live" data.
  const { data: nowPlaying } = await supabase
    .schema('radio')
    .from('now_playing')
    .select('*')
    .limit(1);

  const row = nowPlaying?.[0] ?? null;

  return new Response(JSON.stringify({
    managedPlayoutActive: row !== null,
    nowPlaying: row,
    serverTimestamp: new Date().toISOString()
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
});
