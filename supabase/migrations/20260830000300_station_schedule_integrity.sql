-- Cross-table semantics that cannot be represented safely by a CHECK constraint.
create function app.enforce_station_source_semantics() returns trigger
language plpgsql set search_path = '' as $$
declare provider_kind text;
begin
  select p.provider_type into provider_kind
  from app.content_providers p
  where p.id = new.provider_id and p.deleted_at is null;

  if provider_kind is null then
    raise exception 'station provider is missing or archived';
  end if;

  if new.station_source = 'INTERNAL'::app.station_source then
    if provider_kind <> 'INTERNAL' or new.stream_type <> 'INTERNAL' then
      raise exception 'INTERNAL station requires an INTERNAL provider and stream type';
    end if;
  else
    if provider_kind = 'INTERNAL' or new.stream_type = 'INTERNAL' then
      raise exception 'EXTERNAL station cannot use an INTERNAL provider or stream type';
    end if;
  end if;

  if new.stream_url !~ '^https?://[^[:space:]]+$'
     or (new.fallback_stream_url is not null and new.fallback_stream_url !~ '^https?://[^[:space:]]+$') then
    raise exception 'station stream URLs must be absolute HTTP(S) URLs';
  end if;
  return new;
end $$;
revoke all on function app.enforce_station_source_semantics() from public, anon, authenticated;
grant execute on function app.enforce_station_source_semantics() to service_role;

create trigger stations_source_semantics
before insert or update of provider_id, station_source, stream_type, stream_url, fallback_stream_url
on app.stations for each row execute function app.enforce_station_source_semantics();

create function app.smallint_array_is_unique(values_to_check smallint[]) returns boolean
language sql immutable strict set search_path = '' as $$
  select cardinality(values_to_check) = count(distinct value)
  from unnest(values_to_check) as value
$$;
revoke all on function app.smallint_array_is_unique(smallint[]) from public, anon, authenticated;
grant execute on function app.smallint_array_is_unique(smallint[]) to service_role;

alter table app.schedules add constraint schedules_weekdays_unique_check
  check (days_of_week is null or app.smallint_array_is_unique(days_of_week));
