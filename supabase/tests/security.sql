-- Execute against the isolated bootstrap + migration database. Rolls back its test data.
\set ON_ERROR_STOP on
begin;
insert into auth.users values ('10000000-0000-0000-0000-000000000001'), ('10000000-0000-0000-0000-000000000002');
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $$
declare result jsonb; payload jsonb := '{"event":{"id":"20000000-0000-0000-0000-000000000001","title":"test","date":"2026-09-28"}}';
begin
  result := public.monthly_plan_push('20000000-0000-0000-0000-000000000001',0,'30000000-0000-0000-0000-000000000001',payload,false);
  if (result->>'revision')::int <> 1 then raise exception 'Create revision'; end if;
  result := public.monthly_plan_push('20000000-0000-0000-0000-000000000001',0,'30000000-0000-0000-0000-000000000001',payload,false);
  if (result->>'revision')::int <> 1 then raise exception 'Retry duplicated mutation'; end if;
  result := public.monthly_plan_push('20000000-0000-0000-0000-000000000001',0,'30000000-0000-0000-0000-000000000002',payload,false);
  if result->>'mutation_id' <> '30000000-0000-0000-0000-000000000001' then raise exception 'Stale write overwritten'; end if;
  result := public.monthly_plan_push('20000000-0000-0000-0000-000000000001',1,'30000000-0000-0000-0000-000000000002',payload,false);
  if (result->>'revision')::int <> 2 then raise exception 'Edit revision'; end if;
  result := public.monthly_plan_push('20000000-0000-0000-0000-000000000001',2,'30000000-0000-0000-0000-000000000003',null,true);
  if result->'value' <> 'null'::jsonb or not (result->>'deleted')::boolean then raise exception 'Delete retained body'; end if;
  if (select count(*) from public.monthly_plan_records) <> 1 then raise exception 'Own record invisible'; end if;
  begin
    update public.monthly_plan_records set revision = 100;
    raise exception 'Direct write unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.monthly_plan_push('20000000-0000-0000-0000-000000000002',0,'30000000-0000-0000-0000-000000000001',payload,false);
    raise exception 'Mismatched payload id accepted';
  exception when invalid_parameter_value then null; end;
end $$;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $$
begin
  if (select count(*) from public.monthly_plan_records) <> 0 then raise exception 'RLS leaked account A'; end if;
  perform public.monthly_plan_push('20000000-0000-0000-0000-000000000001',0,'30000000-0000-0000-0000-000000000004',null,true);
  if (select count(*) from public.monthly_plan_records) <> 1 then raise exception 'Independent account write failed'; end if;
end $$;
set local request.jwt.claim.sub = '';
do $$ begin
  begin
    perform public.monthly_plan_push('20000000-0000-0000-0000-000000000002',0,'30000000-0000-0000-0000-000000000005',null,true);
    raise exception 'Missing identity accepted';
  exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  begin
    perform * from public.monthly_plan_records;
    raise exception 'Anonymous read allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.monthly_plan_push('20000000-0000-0000-0000-000000000002',0,'30000000-0000-0000-0000-000000000005',null,true);
    raise exception 'Anonymous push allowed';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo 'PASS: ownership, RLS, anonymous access, direct-write denial, CAS, retry, tombstone, payload checks'
