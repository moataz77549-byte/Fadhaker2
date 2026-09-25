-- Bind READY to the checksum metadata written with the immutable Storage object.
do $migration$
declare
  definition text;
  marker text := 'processed Storage checksum metadata mismatch';
begin
  select pg_get_functiondef(
    'app.complete_media_processing_job(uuid,uuid,text,bigint,text,text,text,text,text,text,integer,integer,smallint,bigint,bigint,integer,jsonb)'::regprocedure
  ) into definition;
  if position(marker in definition)=0 then
    definition := replace(definition,
$old$  if v_storage_size<>p_output_size_bytes or v_storage_mime<>p_output_mime_type then
    raise exception 'processed Storage metadata mismatch';
  end if;$old$,
$new$  if v_storage_size<>p_output_size_bytes or v_storage_mime<>p_output_mime_type then
    raise exception 'processed Storage metadata mismatch';
  end if;
  if lower(coalesce(v_object.user_metadata->>'sha256',''))<>p_output_sha256 then
    raise exception 'processed Storage checksum metadata mismatch';
  end if;$new$);
    if position(marker in definition)=0 then
      raise exception 'could not patch complete_media_processing_job checksum guard';
    end if;
    execute definition;
  end if;
end
$migration$;
