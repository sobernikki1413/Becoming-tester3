-- Becoming membership foundation (STAGED; not applied by committing this file)
-- Run in Supabase SQL Editor only after backing up and reviewing production settings.
-- This migration never charges money, never creates a paid subscription, and does
-- not impose a premium gate on existing free recovery tools.
--
-- Memberships are maintained on the server. Clients may READ their own status
-- but cannot insert, update, or delete entitlements.
-- Existing users do not lose access or silently consume a seven-day trial.

begin;

create table if not exists public.becoming_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  premium_until timestamptz,
  premium_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint becoming_memberships_trial_dates
    check (
      (trial_started_at is null and trial_ends_at is null)
      or (trial_started_at is not null and trial_ends_at = trial_started_at + interval '7 days')
    ),
  constraint becoming_memberships_source_check
    check (premium_source is null or premium_source in ('subscription','gift','scholarship','pay_it_forward','admin')),
  constraint becoming_memberships_premium_fields_check
    check ((premium_until is null and premium_source is null)
      or (premium_until is not null and premium_source is not null))
);

alter table public.becoming_memberships enable row level security;

drop policy if exists "Member can read own membership" on public.becoming_memberships;
create policy "Member can read own membership"
on public.becoming_memberships
for select to authenticated
using ((select auth.uid()) = user_id);

-- No client-side modification permission. Premium grants must come from a
-- trusted payment webhook or authorized server operation, never a browser.
revoke all on table public.becoming_memberships from anon, authenticated;
grant select on table public.becoming_memberships to authenticated;

-- Make membership rows on account creation, but do NOT start a trial yet.
-- The launch trial activation flow will be a separate reviewed server action.
create or replace function public.becoming_initialize_membership()
returns trigger language plpgsql security definer
set search_path = '' as $$
begin
  insert into public.becoming_memberships(user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.becoming_initialize_membership() from public, anon, authenticated;

drop trigger if exists becoming_membership_user_created on auth.users;
create trigger becoming_membership_user_created
after insert on auth.users
for each row execute function public.becoming_initialize_membership();

-- Ensure previously registered members have records without starting trial.
insert into public.becoming_memberships(user_id)
select id from auth.users
on conflict (user_id) do nothing;

commit;

-- Pending before release:
-- 1. Audit RLS and verify access using two independent signed-in test accounts.
-- 2. Authorize an explicit server-side seven-day trial-start workflow.
-- 3. Implement server-verified entitlement checks in Premium features.
-- 4. Add secure checkout, webhook verification, billing history and cancellation.
-- 5. Test expired trials, payment failures, 3-day grace period and reversion to free tools.
