-- Run once in a new Supabase project's SQL Editor. No private keys belong in this file.
begin;
create table public.monthly_plan_records (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (length(id) between 1 and 80),
  revision bigint not null check (revision > 0),
  mutation_id uuid not null,
  value jsonb,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  check (deleted or (value is not null and jsonb_typeof(value) = 'object')),
  check (value is null or octet_length(value::text) <= 32000)
);
alter table public.monthly_plan_records enable row level security;
revoke all on public.monthly_plan_records from anon, authenticated;
grant select on public.monthly_plan_records to authenticated;
create policy own_records on public.monthly_plan_records for select to authenticated
  using ((select auth.uid()) = user_id);

-- All writes go through compare-and-swap. Deletes remain as tombstones for offline Macs.
create function public.monthly_plan_push(
  p_id text, p_base_revision bigint, p_mutation_id uuid, p_value jsonb, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  existing public.monthly_plan_records%rowtype;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_id is null or p_base_revision is null or p_base_revision < 0 or p_mutation_id is null or p_deleted is null
    or not (p_id ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' or p_id ~ '^place:[a-f0-9]{64}$')
    or (not p_deleted and (p_value is null or jsonb_typeof(p_value) <> 'object'))
    or octet_length(p_value::text) > 32000
  then raise exception 'Invalid record' using errcode = '22023'; end if;
  if not p_deleted then
    if p_id like 'place:%' then
      if (p_value->>'placeKey') is distinct from substring(p_id from 7)
        or coalesce(p_value->>'googlePlaceID','') !~ '^[A-Za-z0-9_-]{1,255}$'
        or p_value ? 'event'
      then raise exception 'Invalid place' using errcode = '22023'; end if;
    else
      if jsonb_typeof(p_value->'event') is distinct from 'object'
        or (p_value->'event'->>'id') is distinct from p_id
        or length(coalesce(p_value->'event'->>'title','')) not between 1 and 100
        or coalesce(p_value->'event'->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or p_value ? 'placeKey' or p_value ? 'googlePlaceID'
      then raise exception 'Invalid event' using errcode = '22023'; end if;
    end if;
  end if;
  -- Serialize even first inserts; no device clocks determine the winner.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text || ':' || p_id, 0));
  select * into existing from public.monthly_plan_records where user_id = owner_id and id = p_id for update;
  if found then
    if existing.mutation_id = p_mutation_id or existing.revision <> p_base_revision then
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
revoke all on function public.monthly_plan_push(text,bigint,uuid,jsonb,boolean) from public, anon;
grant execute on function public.monthly_plan_push(text,bigint,uuid,jsonb,boolean) to authenticated;
commit;
