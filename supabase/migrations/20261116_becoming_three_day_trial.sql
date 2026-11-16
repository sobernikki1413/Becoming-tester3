-- Becoming: change NEW Premium trials to three days.
-- Run in Supabase SQL Editor only after reviewing the membership foundation.
-- Existing seven-day trials retain their originally promised expiration dates.
-- This does not start trials, modify Premium payments, or alter free recovery tools.
begin;

alter table public.becoming_memberships
  drop constraint if exists becoming_memberships_trial_dates;
alter table public.becoming_memberships
  add constraint becoming_memberships_trial_dates
  check (
    (trial_started_at is null and trial_ends_at is null)
    or (
      trial_started_at is not null and trial_ends_at is not null
      and trial_ends_at in (
        trial_started_at + interval '3 days',
        trial_started_at + interval '7 days'
      )
    )
  );

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

  select trial_started_at,trial_ends_at,premium_until
    into v_started,v_ends,v_premium_until
  from public.becoming_memberships
  where user_id=v_uid
  for update;

  if v_started is not null or v_ends is not null then
    raise exception 'Your trial has already been used';
  end if;

  if v_premium_until is not null and v_premium_until > now() then
    raise exception 'Your account already has active Premium access';
  end if;

  update public.becoming_memberships
  set trial_started_at=now(),
      trial_ends_at=now()+interval '3 days',
      updated_at=now()
  where user_id=v_uid
  returning trial_ends_at into v_ends;

  return v_ends;
end;
$$;
revoke all on function public.becoming_start_trial() from public,anon;
grant execute on function public.becoming_start_trial() to authenticated;
commit;

-- Required prior to production:
-- Apply the existing membership foundation and trial setup before this migration.
-- Verify a new member receives exactly 72 hours and cannot restart the trial.
-- Verify existing seven-day trial_end dates remain unchanged.
-- Confirm the user-facing trial terms and Premium access tests match.
