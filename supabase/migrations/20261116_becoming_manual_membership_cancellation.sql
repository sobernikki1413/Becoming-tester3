-- Manual Cash App membership cancellation (no auto-renewal).
-- Records the member's choice; does not shorten already-paid access.
begin;
alter table public.becoming_memberships
  add column if not exists cancellation_requested_at timestamptz;

create or replace function public.becoming_cancel_manual_membership()
returns timestamptz
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cancelled timestamptz;
begin
  if v_uid is null then
    raise exception 'Please sign in' using errcode='42501';
  end if;

  -- A trial or scholarship is not a paid manual membership to cancel.
  update public.becoming_memberships m
  set cancellation_requested_at=coalesce(m.cancellation_requested_at,now()),
      updated_at=now()
  where m.user_id=v_uid
    and m.premium_source='subscription'
    and m.premium_until>now()
  returning m.cancellation_requested_at into v_cancelled;

  if v_cancelled is null then
    raise exception 'There is no active paid manual membership to cancel' using errcode='P0001';
  end if;
  return v_cancelled;
end;
$$;
revoke all on function public.becoming_cancel_manual_membership() from public,anon;
grant execute on function public.becoming_cancel_manual_membership() to authenticated;
commit;
-- Note: Manual Cash App payments never automatically renew.
-- This records a cancellation request and retains access through premium_until.
-- Payment disputes, refunds, and any independent external payment arrangement
-- still require support; this is not a refund or cancellation of external services.
