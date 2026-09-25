-- Qualify RETURN TABLE names inside stale recovery on the applied DEVELOPMENT database.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef('app.recover_stale_media_processing_jobs(integer)'::regprocedure)
    into definition;
  if definition like '%where job_id=v_job.id and claim_token=v_job.claim_token%' then
    definition := replace(definition,
      'update app.media_processing_attempts set status=',
      'update app.media_processing_attempts as stale_attempt set status=');
    definition := replace(definition,
      'where job_id=v_job.id and claim_token=v_job.claim_token and status=',
      'where stale_attempt.job_id=v_job.id and stale_attempt.claim_token=v_job.claim_token and stale_attempt.status=');
    execute definition;
  end if;
end
$migration$;
