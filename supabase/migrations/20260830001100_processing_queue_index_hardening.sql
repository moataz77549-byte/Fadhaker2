-- Match the hot claim predicate and index every new foreign-key lookup direction.
drop index if exists app.media_processing_jobs_claim_idx;
create index media_processing_jobs_claim_idx
  on app.media_processing_jobs (profile_id,priority desc,next_attempt_at,created_at,id)
  where status in ('PENDING','RETRY_WAIT');
create index if not exists processed_media_variants_attempt_idx
  on app.processed_media_variants (attempt_id);
