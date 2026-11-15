-- Becoming: isolated scholarship-code rehearsal, no Premium grants
-- Apply only to the Becoming-connected Supabase project after the admin migrations.
-- BEC-TEST codes are not real scholarships and can never grant Premium access.
begin;
create table if not exists public.becoming_scholarship_test_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default now(),
  redeemed_by uuid references auth.users(id),
  redeemed_at timestamptz,
  constraint becoming_test_redemption_pair check (
    (redeemed_by is null and redeemed_at is null)
    or (redeemed_by is not null and redeemed_at is not null)
  )
);
alter table public.becoming_scholarship_test_codes enable row level security;
revoke all on public.becoming_scholarship_test_codes from public,anon,authenticated;
grant all on public.becoming_scholarship_test_codes to service_role;

create or replace function public.becoming_admin_issue_test_code()
returns text language plpgsql security definer set search_path=''
as $$
declare v_code text;
begin
  if (select auth.uid()) is null or not exists(
    select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
  ) then raise exception 'Administrator access required' using errcode='42501'; end if;
  v_code := 'BEC-TEST-'||upper(encode(extensions.gen_random_bytes(18),'hex'));
  insert into public.becoming_scholarship_test_codes(code_hash,issued_by)
  values(encode(extensions.digest(v_code,'sha256'),'hex'),(select auth.uid()));
  return v_code;
end;
$$;
revoke all on function public.becoming_admin_issue_test_code() from public,anon,authenticated;
grant execute on function public.becoming_admin_issue_test_code() to authenticated;

create or replace function public.becoming_redeem_test_code(p_code text)
returns text language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first' using errcode='42501';
  end if;
  if p_code is null or p_code !~ '^BEC-TEST-[0-9A-Fa-f]{36}$' then
    return 'INVALID';
  end if;
  select id into v_id from public.becoming_scholarship_test_codes
   where code_hash=encode(extensions.digest(upper(p_code),'sha256'),'hex')
     and redeemed_at is null for update;
  if v_id is null then return 'INVALID_OR_USED'; end if;
  update public.becoming_scholarship_test_codes
   set redeemed_by=(select auth.uid()),redeemed_at=now()
   where id=v_id and redeemed_at is null;
  return 'TEST_REDEEMED';
end;
$$;
revoke all on function public.becoming_redeem_test_code(text) from public,anon,authenticated;
grant execute on function public.becoming_redeem_test_code(text) to authenticated;

create or replace function public.becoming_admin_test_counts()
returns table(issued bigint, redeemed bigint)
language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null or not exists(
    select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
  ) then raise exception 'Administrator access required' using errcode='42501'; end if;
  return query select
    count(*) filter (where c.redeemed_at is null),
    count(*) filter (where c.redeemed_at is not null)
  from public.becoming_scholarship_test_codes c;
end;
$$;
revoke all on function public.becoming_admin_test_counts() from public,anon,authenticated;
grant execute on function public.becoming_admin_test_counts() to authenticated;
commit;

-- Safety: no reference to becoming_memberships, no Premium grants,
-- no billing and no changes to real scholarship inventory.
-- Manually test admin issue, non-admin access rejection, single-use redemption.
