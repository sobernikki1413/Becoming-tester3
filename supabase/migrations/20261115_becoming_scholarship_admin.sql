-- Becoming: authorized scholarship dashboard functions (STAGED)
-- Apply AFTER the two 20261115 membership/scholarship migrations.
-- Only manually enrolled admin account UUIDs can generate or cancel codes.
-- Do not put any service-role secret or private signing credential in browser code.
begin;

create table if not exists public.becoming_admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.becoming_admin_users enable row level security;
revoke all on public.becoming_admin_users from public, anon, authenticated;
grant all on public.becoming_admin_users to service_role;
-- Bootstrap your OWN account only, manually in SQL Editor after verifying UUID:
-- insert into public.becoming_admin_users(user_id) values ('YOUR-VERIFIED-AUTH-USER-UUID')
-- on conflict (user_id) do nothing;
-- Never populate this table from a self-service browser registration flow.

create or replace function public.becoming_admin_summary()
returns table(funded bigint, issued bigint, redeemed bigint, voided bigint)
language plpgsql security definer set search_path=''
as $$
begin
 if (select auth.uid()) is null or not exists (
   select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
 ) then raise exception 'Administrator access required' using errcode='42501'; end if;
 return query
 select count(*) filter (where c.status='funded'),
        count(*) filter (where c.status='issued'),
        count(*) filter (where c.status='redeemed'),
        count(*) filter (where c.status='void')
 from public.becoming_scholarship_codes c;
end;
$$;
revoke all on function public.becoming_admin_summary() from public, anon, authenticated;
grant execute on function public.becoming_admin_summary() to authenticated;

create or replace function public.becoming_admin_issue_code(p_funding_reference text)
returns table(code text, code_id uuid)
language plpgsql security definer set search_path=''
as $$
declare
  v_raw text;
  v_id uuid;
begin
 if (select auth.uid()) is null or not exists (
   select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
 ) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if nullif(btrim(p_funding_reference),'') is null or length(p_funding_reference)>200 then
   raise exception 'A verified funding reference (1-200 characters) is required';
 end if;
 v_raw := 'BEC-'||upper(encode(extensions.gen_random_bytes(18),'hex'));
 insert into public.becoming_scholarship_codes
  (code_hash,status,funding_reference,issued_at)
 values
  (encode(extensions.digest(v_raw,'sha256'),'hex'),'issued',btrim(p_funding_reference),now())
 returning id into v_id;
 return query select v_raw,v_id;
end;
$$;
revoke all on function public.becoming_admin_issue_code(text) from public, anon, authenticated;
grant execute on function public.becoming_admin_issue_code(text) to authenticated;

create or replace function public.becoming_admin_issued_codes()
returns table(code_id uuid, issued_at timestamptz, funding_reference text)
language plpgsql security definer set search_path=''
as $$
begin
 if (select auth.uid()) is null or not exists (
   select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
 ) then raise exception 'Administrator access required' using errcode='42501'; end if;
 return query select c.id,c.issued_at,c.funding_reference
  from public.becoming_scholarship_codes c
  where c.status='issued' order by c.issued_at desc limit 100;
end;
$$;
revoke all on function public.becoming_admin_issued_codes() from public, anon, authenticated;
grant execute on function public.becoming_admin_issued_codes() to authenticated;

create or replace function public.becoming_admin_void_code(p_code_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $$
begin
 if (select auth.uid()) is null or not exists (
   select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
 ) then raise exception 'Administrator access required' using errcode='42501'; end if;
 update public.becoming_scholarship_codes
 set status='void'
 where id=p_code_id and status='issued';
 return found;
end;
$$;
revoke all on function public.becoming_admin_void_code(uuid) from public, anon, authenticated;
grant execute on function public.becoming_admin_void_code(uuid) to authenticated;

commit;

-- Before issuing real scholarships:
-- 1. Admin-only enrollment via SQL editor; verify UUID and restrict admin account MFA.
-- 2. Run a two-account authorization test: non-admin cannot call these RPCs.
-- 3. Test one-time code visibility, redemption, re-use, voiding, and funding accounting.
-- 4. Verify funded awards based on separately reconciled funds; an entered reference
--    is not proof of funding and the dashboard is NOT a payments ledger.
