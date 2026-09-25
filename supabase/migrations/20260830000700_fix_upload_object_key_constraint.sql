alter table app.media_upload_intents drop constraint media_upload_intents_check2;
alter table app.media_upload_intents add constraint media_upload_intents_object_key_check
  check (object_key = 'media/'||media_id::text||'/original/'||id::text||'.'||extension);
