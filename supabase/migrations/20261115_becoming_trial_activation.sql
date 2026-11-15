-- Becoming: secure, one-time, seven-day premium trial.
-- STAGED: committing this file does NOT install it in Supabase.
-- Install after 20261115_becoming_memberships_foundation.sql.
-- This adds a server-authoritative function. It DOES NOT automatically start
-- trials, take payment, enable billing, or gate permanently free recovery tools.
begin;

create or replace function public.becoming_start_trial()
returns timestamptz
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_started timestamptz;
  v_ends timestamptz;
  v_premium_until timestamptz;
begin
  v_uid := (select auth.uid());
  if v_uid is null then
    raise exception 'Sign in to start a trial';
  end if;

  insert into public.becoming_memberships(user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  -- Serializes concurrent attempts for a given account. Once trial_started_at
  -- is set, it cannot be restarted or refreshed through this function.
  select trial_started_at,trial_ends_at,premium_until
    into v_started,v_ends,v_premium_until
  from public.becoming_memberships
  where user_id=v_uid
  for update;

  if v_started is not null or v_ends is not null then
    raise exception 'Your seven-day trial has already been used';
  end if;

  if v_premium_until is not null and v_premium_until > now() then
    raise exception 'Your account already has active Premium access';
  end if;

  update public.becoming_memberships
  set trial_started_at=now(),
      trial_ends_at=now()+interval '7 days',
      updated_at=now()
  where user_id=v_uid
  returning trial_ends_at into v_ends;

  return v_ends;
end;
$$;

revoke all on function public.becoming_start_trial() from public,anon;
grant execute on function public.becoming_start_trial() to authenticated;

-- Explicit server-readable status for the current user. No other member's
-- membership or dates are returned to this caller.
create or replace function public.becoming_my_membership_status()
returns table (
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  premium_until timestamptz,
  premium_source text,
  trial_used boolean,
  trial_active boolean,
  premium_active boolean
)
language sql stable security definer
set search_path = ''
as $$
  select m.trial_started_at,
         m.trial_ends_at,
         m.premium_until,
         m.premium_source,
         (m.trial_started_at is not null),
         (m.trial_ends_at > now()),
         (m.premium_until > now())
  from public.becoming_memberships m
  where m.user_id=(select auth.uid())
  limit 1;
$$;
revoke all on function public.becoming_my_membership_status() from public,anon;
grant execute on function public.becoming_my_membership_status() to authenticated;
commit;

-- BEFORE CONNECTING ANY START BUTTON:
-- * Confirm existing trial records and scholarships don't regress.
-- * Confirm authenticated member cannot modify their membership row directly.
-- * Verify one-time use, concurrent calls, and two-account isolation.
-- * Build real premium entitlements and an accurate full-access list.
-- * Confirm seven-day trial has no card, no charges, and no auto-renewal.
