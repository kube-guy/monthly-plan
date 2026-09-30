-- Extend the existing per-user sync records with immutable place summaries.
-- Run once after 202609280001_initial.sql. Existing schedules are untouched.
begin;
create or replace function public.monthly_plan_push(
  p_id text, p_base_revision bigint, p_mutation_id uuid, p_value jsonb, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  existing public.monthly_plan_records%rowtype;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_id is null or p_base_revision is null or p_base_revision < 0 or p_mutation_id is null or p_deleted is null
    or not (p_id ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'
      or p_id ~ '^place:[a-f0-9]{64}$' or p_id ~ '^summary:[a-f0-9]{64}$')
    or (not p_deleted and (p_value is null or jsonb_typeof(p_value) <> 'object'))
    or octet_length(p_value::text) > 32000
  then raise exception 'Invalid record' using errcode = '22023'; end if;
  if p_id like 'summary:%' and p_deleted then
    raise exception 'Saved summaries are immutable' using errcode = '22023';
  end if;
  if not p_deleted then
    if p_id like 'summary:%' then
      if (p_value->>'summaryKey') is distinct from substring(p_id from 9)
        or jsonb_typeof(p_value->'summary') is distinct from 'object'
        or p_value ? 'event' or p_value ? 'placeKey' or p_value ? 'googlePlaceID'
      then raise exception 'Invalid summary' using errcode = '22023'; end if;
      if length(coalesce(p_value->'summary'->>'parking','')) not between 1 and 4000
        or length(coalesce(p_value->'summary'->>'reviews','')) not between 1 and 4000
        or jsonb_typeof(p_value->'summary'->'sources') is distinct from 'array'
      then raise exception 'Invalid summary' using errcode = '22023'; end if;
      if jsonb_array_length(p_value->'summary'->'sources') not between 1 and 10
        or exists (
          select 1 from jsonb_array_elements(p_value->'summary'->'sources') as source(value)
          where jsonb_typeof(source.value) <> 'object'
            or length(coalesce(source.value->>'title','')) not between 1 and 300
            or length(coalesce(source.value->>'url','')) not between 9 and 2000
            or coalesce(source.value->>'url','') !~ '^https://[^/@[:space:]]+([/?#]|$)'
        )
      then raise exception 'Invalid summary source' using errcode = '22023'; end if;
    elsif p_id like 'place:%' then
      if (p_value->>'placeKey') is distinct from substring(p_id from 7)
        or coalesce(p_value->>'googlePlaceID','') !~ '^[A-Za-z0-9_-]{1,255}$'
        or p_value ? 'event' or p_value ? 'summaryKey' or p_value ? 'summary'
      then raise exception 'Invalid place' using errcode = '22023'; end if;
    else
      if jsonb_typeof(p_value->'event') is distinct from 'object'
        or (p_value->'event'->>'id') is distinct from p_id
        or length(coalesce(p_value->'event'->>'title','')) not between 1 and 100
        or coalesce(p_value->'event'->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or p_value ? 'placeKey' or p_value ? 'googlePlaceID'
        or p_value ? 'summaryKey' or p_value ? 'summary'
      then raise exception 'Invalid event' using errcode = '22023'; end if;
    end if;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text || ':' || p_id, 0));
  select * into existing from public.monthly_plan_records where user_id = owner_id and id = p_id for update;
  if found then
    -- The first saved summary wins, even when two Macs finish their initial lookup together.
    if p_id like 'summary:%' or existing.mutation_id = p_mutation_id or existing.revision <> p_base_revision then
      return to_jsonb(existing);
    end if;
    update public.monthly_plan_records set revision = revision + 1, mutation_id = p_mutation_id,
      value = case when p_deleted then null else p_value end, deleted = p_deleted, updated_at = now()
      where user_id = owner_id and id = p_id returning * into existing;
  else
    if p_base_revision <> 0 then raise exception 'Missing base revision' using errcode = '40001'; end if;
    insert into public.monthly_plan_records(user_id,id,revision,mutation_id,value,deleted)
      values(owner_id,p_id,1,p_mutation_id,case when p_deleted then null else p_value end,p_deleted)
      returning * into existing;
  end if;
  return to_jsonb(existing);
end;
$$;
commit;
