-- Search normalization is separate from source text; source text is immutable.
create or replace function app.normalize_arabic_search(p_text text)
returns text language sql immutable strict set search_path = '' as $$
  select btrim(regexp_replace(
    translate(lower(translate(p_text,
      'ًٌٍَُِّْٰـ', '')), 'أإآٱىؤئ', 'اااايوي'),
    '[[:space:]]+', ' ', 'g'))
$$;
revoke all on function app.normalize_arabic_search(text) from public;
grant execute on function app.normalize_arabic_search(text) to anon, authenticated, service_role;

alter table app.hadiths add column if not exists search_text text
  generated always as (app.normalize_arabic_search(
    coalesce(title, '') || ' ' || hadith_text || ' ' || coalesce(narrator, ''))) stored;
alter table app.adhkar add column if not exists search_text text
  generated always as (app.normalize_arabic_search(
    coalesce(title, '') || ' ' || text_ar)) stored;
create index if not exists hadiths_search_trgm_idx on app.hadiths
  using gin (search_text gin_trgm_ops) where is_active;
create index if not exists adhkar_search_trgm_idx on app.adhkar
  using gin (search_text gin_trgm_ops) where is_active and verified;

create or replace function app.search_hadiths(p_query text default '',
  p_limit integer default 20, p_offset integer default 0)
returns setof app.hadiths language sql stable security invoker set search_path = '' as $$
  select h.* from app.hadiths h
  where h.is_active and (coalesce(p_query, '') = '' or
    h.search_text like '%' || app.normalize_arabic_search(p_query) || '%')
  order by h.synced_at desc, h.id
  limit least(greatest(p_limit, 1), 30)
  offset least(greatest(p_offset, 0), 3000)
$$;
revoke all on function app.search_hadiths(text, integer, integer) from public;
grant execute on function app.search_hadiths(text, integer, integer) to anon, authenticated, service_role;
