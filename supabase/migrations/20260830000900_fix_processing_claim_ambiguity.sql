-- Hotfix for the already-applied DEVELOPMENT migration. Fresh databases receive
-- the qualified UPDATE directly from 008; this remains a safe no-op there.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef('app.claim_media_processing_job(text,text,text,integer,smallint)'::regprocedure)
    into definition;
  if definition like '%claim_token=claim_token+1%' then
    definition := replace(definition,
      'update app.media_processing_jobs set',
      'update app.media_processing_jobs as claimed_job set');
    definition := replace(definition,'attempts=attempts+1','attempts=claimed_job.attempts+1');
    definition := replace(definition,'claim_token=claim_token+1','claim_token=claimed_job.claim_token+1');
    execute definition;
  end if;
end
$migration$;
