-- Becoming: one-year scholarship inventory and single-use redemption
-- STAGED migration. Apply AFTER 20261115_becoming_memberships_foundation.sql.
-- No payment collection, charges, automatic renewals, or changes to free tools.
-- Scholarship funding must be verified by an administrator before issuing codes.
begin;

-- Supabase normally installs pgcrypto into extensions.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.becoming_scholarship_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  duration_months integer not null default 12 check (duration_months = 12),
  status text not null default 'funded' check (status in ('funded','issued','redeemed','void')),
  funding_reference text,
  created_at timestamptz not null default now(),
  issued_at timestamptz,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  constraint becoming_scholarship_redeemed_consistency
    check (
      (status = 'redeemed' and redeemed_at is not null and redeemed_by is not null)
      or (status <> 'redeemed' and redeemed_at is null and redeemed_by is null)
    )
);

alter table public.becoming_scholarship_codes enable row level security;
-- No public read policies: codes and recipient identities are administrator-only.
revoke all on public.becoming_scholarship_codes from public, anon, authenticated;
grant all on public.becoming_scholarship_codes to service_role;

-- Admin-only: creates one funded slot and generates a strong one-time code.
-- Caller MUST first confirm that this full year is funded and record the funding reference.
-- Only the service role may execute; never put the service role key in the website.
create or replace function public.becoming_admin_issue_scholarship(p_funding_reference text)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Administrator access required';
  end if;
  if nullif(btrim(p_funding_reference),'') is null then
    raise exception 'Funding reference is required';
  end if;

  v_code := 'BEC-' || upper(encode(extensions.gen_random_bytes(18),'hex'));
  insert into public.becoming_scholarship_codes
    (code_hash,status,funding_reference,issued_at)
  values
    (encode(extensions.digest(v_code,'sha256'),'hex'),'issued',p_funding_reference,now());
  return v_code; -- show once to the admin; store only the hash
end;
$$;
revoke all on function public.becoming_admin_issue_scholarship(text) from public, anon, authenticated;
grant execute on function public.becoming_admin_issue_scholarship(text) to service_role;

-- Redeem a single-use code for 12 calendar months, securely on the server.
-- One user's active Premium grant is not overwritten or shortened.
-- Database locking prevents two people redeeming the same code.
create or replace function public.becoming_redeem_scholarship(p_code text)
returns timestamptz
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_code_id uuid;
  v_existing_until timestamptz;
  v_end timestamptz;
begin
  v_uid := (select auth.uid());
  if v_uid is null then
    raise exception 'Sign in to redeem a scholarship';
  end if;
  if p_code is null or length(p_code) > 128
     or p_code !~ '^BEC-[0-9A-Fa-f]{36}$' then
    raise exception 'Invalid scholarship code';
  end if;

  select id into v_code_id
  from public.becoming_scholarship_codes
  where code_hash = encode(extensions.digest(upper(p_code),'sha256'),'hex')
    and status='issued'
  for update;

  if v_code_id is null then
    raise exception 'This code is invalid or has already been used';
  end if;

  insert into public.becoming_memberships(user_id)
  values (v_uid) on conflict (user_id) do nothing;
  select premium_until into v_existing_until
  from public.becoming_memberships
  where user_id=v_uid for update;

  if v_existing_until > now() then
    raise exception 'Your account already has active Premium access. Contact support to arrange your award.';
  end if;

  v_end := now() + interval '12 months';
  update public.becoming_memberships
  set premium_until=v_end,premium_source='scholarship',updated_at=now()
  where user_id=v_uid;

  update public.becoming_scholarship_codes
  set status='redeemed',redeemed_at=now(),redeemed_by=v_uid
  where id=v_code_id;

  return v_end;
end;
$$;
revoke all on function public.becoming_redeem_scholarship(text) from public, anon;
grant execute on function public.becoming_redeem_scholarship(text) to authenticated;

-- Administrator-only aggregate inventory. No member identities returned.
create or replace function public.becoming_admin_scholarship_counts()
returns table(funded bigint,issued bigint,redeemed bigint,voided bigint)
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Administrator access required';
  end if;
  return query
    select count(*) filter (where status='funded'),
           count(*) filter (where status='issued'),
           count(*) filter (where status='redeemed'),
           count(*) filter (where status='void')
    from public.becoming_scholarship_codes;
end;
$$;
revoke all on function public.becoming_admin_scholarship_counts() from public, anon, authenticated;
grant execute on function public.becoming_admin_scholarship_counts() to service_role;

commit;

-- Not yet deployed or tested:
-- * Verify the initial membership migration was applied.
-- * Validate RPC privileges/RLS and redemption concurrency with two test accounts.
-- * Add a member-facing code field and admin-only dashboard in a separate release.
-- * Require confirmed annual funding before calling the issuing function.
-- * Review random-drawing/giveaway rules before conducting any raffle.
-- * Never expose service_role keys or returned raw codes in public logs.
