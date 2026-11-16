-- Becoming: authoritative read-only premium entitlement check.
-- STAGED: repository commit does NOT install this in Supabase.
-- Apply after the membership and trial activation migrations.
-- This does not start any trial, change existing memberships, charge anyone,
-- or restrict access to permanently free recovery tools.
begin;

create or replace function public.becoming_has_premium_access()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select (m.trial_ends_at > now() or m.premium_until > now())
    from public.becoming_memberships m
    where m.user_id = (select auth.uid())
    limit 1
  ),false);
$$;

revoke all on function public.becoming_has_premium_access() from public,anon;
grant execute on function public.becoming_has_premium_access() to authenticated;
commit;

-- IMPORTANT: Premium database writes must check membership server-side.
-- This read-only function is NOT sufficient as browser-only authorization.
-- Keep core recovery features accessible without Premium.
-- Test signed-out, expired-trial, active-trial, scholarship, and cross-account cases.
