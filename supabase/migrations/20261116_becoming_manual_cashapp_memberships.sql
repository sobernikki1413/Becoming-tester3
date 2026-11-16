-- Becoming: Cash App manual membership requests (STAGED; not applied by GitHub).
-- Apply only after membership foundation and scholarship-admin migrations.
-- No Cash App integration, automatic charges, or browser-side granting of Premium.
-- An administrator MUST independently verify funds in their own Cash App history.
begin;

create table if not exists public.becoming_payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reference_code text not null unique,
  plan text not null check (plan in ('monthly','annual')),
  amount_cents integer not null check (
    (plan='monthly' and amount_cents=699) or
    (plan='annual' and amount_cents=5999)
  ),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  cashapp_transaction_ref text unique,
  constraint becoming_payment_review_state check (
    (status='pending' and reviewed_at is null and reviewed_by is null and cashapp_transaction_ref is null)
    or (status='rejected' and reviewed_at is not null and reviewed_by is not null and cashapp_transaction_ref is null)
    or (status='approved' and reviewed_at is not null and reviewed_by is not null and cashapp_transaction_ref is not null)
  )
);
create index if not exists becoming_payment_request_user_idx
  on public.becoming_payment_requests (user_id, created_at desc);
create index if not exists becoming_payment_request_pending_idx
  on public.becoming_payment_requests (created_at)
  where status='pending';

alter table public.becoming_payment_requests enable row level security;
revoke all on table public.becoming_payment_requests from public, anon, authenticated;
grant select on table public.becoming_payment_requests to authenticated;
drop policy if exists "Members read only own payment requests" on public.becoming_payment_requests;
create policy "Members read only own payment requests"
  on public.becoming_payment_requests for select to authenticated
  using (user_id=(select auth.uid()));

-- Create an unguessable reference associated with the signed-in user.
-- Do NOT put the member's email, username, or recovery history in Cash App notes.
create or replace function public.becoming_request_cashapp_payment(p_plan text)
returns table(reference_code text, amount_cents integer, plan text)
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_amount integer;
  v_code text;
  v_existing public.becoming_payment_requests%rowtype;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if p_plan not in ('monthly','annual') or p_plan is null then
    raise exception 'Choose monthly or annual';
  end if;
  v_amount := case when p_plan='monthly' then 699 else 5999 end;

  -- Prevent generating unlimited pending codes for one account; reuse pending one.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 87132));
  select * into v_existing from public.becoming_payment_requests r
  where r.user_id=v_uid and r.status='pending'
  order by r.created_at desc limit 1;
  if found then
    if v_existing.plan <> p_plan then
      raise exception 'A pending request already exists; contact support to change plans';
    end if;
    return query select v_existing.reference_code,v_existing.amount_cents,v_existing.plan;
    return;
  end if;

  v_code := 'BEC-PAY-'||upper(encode(extensions.gen_random_bytes(10),'hex'));
  insert into public.becoming_payment_requests(user_id,reference_code,plan,amount_cents)
  values(v_uid,v_code,p_plan,v_amount);
  return query select v_code,v_amount,p_plan;
end;
$$;
revoke all on function public.becoming_request_cashapp_payment(text) from public,anon;
grant execute on function public.becoming_request_cashapp_payment(text) to authenticated;

-- Admin-only queue. Never reveal member emails or personal recovery records here.
create or replace function public.becoming_admin_payment_queue()
returns table(request_id uuid, reference_code text, plan text,
  amount_cents integer, status text, created_at timestamptz, reviewed_at timestamptz)
language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.becoming_admin_users a where a.user_id=(select auth.uid())
  ) then raise exception 'Administrator access required' using errcode='42501'; end if;
  return query select r.id,r.reference_code,r.plan,r.amount_cents,r.status,r.created_at,r.reviewed_at
  from public.becoming_payment_requests r
  order by (r.status='pending') desc,r.created_at desc limit 200;
end;
$$;
revoke all on function public.becoming_admin_payment_queue() from public,anon;
grant execute on function public.becoming_admin_payment_queue() to authenticated;

-- Admin must compare code AND amount against Cash App activity before calling.
-- Transaction reference must be independently read from the Cash App log.
-- Unique transaction reference prevents one Cash App payment being reused twice.
create or replace function public.becoming_admin_approve_cashapp_payment(
  p_request_id uuid, p_cashapp_transaction_ref text
)
returns timestamptz
language plpgsql security definer set search_path=''
as $$
declare
  v_admin uuid := (select auth.uid());
  v_req public.becoming_payment_requests%rowtype;
  v_until timestamptz;
  v_reference text := nullif(btrim(p_cashapp_transaction_ref),'');
begin
  if v_admin is null or not exists (
    select 1 from public.becoming_admin_users a where a.user_id=v_admin
  ) then raise exception 'Administrator access required' using errcode='42501'; end if;
  if v_reference is null or length(v_reference)>160 then
    raise exception 'Verified Cash App transaction identifier required (max 160 characters)';
  end if;
  select * into v_req from public.becoming_payment_requests r where r.id=p_request_id for update;
  if not found then raise exception 'Unknown payment request'; end if;
  if v_req.status<>'pending' then raise exception 'Payment request already reviewed'; end if;
  if exists (select 1 from public.becoming_payment_requests r
    where r.cashapp_transaction_ref=v_reference) then
    raise exception 'Cash App transaction already used';
  end if;

  -- Do not overwrite an existing longer trial or scholarship entitlement.
  insert into public.becoming_memberships(user_id) values(v_req.user_id)
    on conflict(user_id) do nothing;
  select greatest(now(),coalesce(m.premium_until,now()))
    + case when v_req.plan='monthly' then interval '1 month' else interval '1 year' end
    into v_until
  from public.becoming_memberships m where m.user_id=v_req.user_id for update;

  update public.becoming_memberships m
    set premium_until=v_until,premium_source='subscription',updated_at=now()
    where m.user_id=v_req.user_id;
  update public.becoming_payment_requests r
    set status='approved',reviewed_at=now(),reviewed_by=v_admin,
        cashapp_transaction_ref=v_reference
    where r.id=p_request_id;
  return v_until;
end;
$$;
revoke all on function public.becoming_admin_approve_cashapp_payment(uuid,text) from public,anon;
grant execute on function public.becoming_admin_approve_cashapp_payment(uuid,text) to authenticated;

create or replace function public.becoming_admin_reject_cashapp_payment(p_request_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_admin uuid := (select auth.uid());
begin
  if v_admin is null or not exists (
    select 1 from public.becoming_admin_users a where a.user_id=v_admin
  ) then raise exception 'Administrator access required' using errcode='42501'; end if;
  update public.becoming_payment_requests r
    set status='rejected',reviewed_at=now(),reviewed_by=v_admin
    where r.id=p_request_id and r.status='pending';
  return found;
end;
$$;
revoke all on function public.becoming_admin_reject_cashapp_payment(uuid) from public,anon;
grant execute on function public.becoming_admin_reject_cashapp_payment(uuid) to authenticated;
commit;

-- PRE-LAUNCH GATES
-- 1. Confirm exact launch prices and Cash App transaction reference format.
-- 2. Run RLS tests with two members and one administrator, including direct table writes.
-- 3. Confirm customer can't approve/reject or view another member's payment request.
-- 4. Verify one-use transaction references; concurrency and repeated clicks.
-- 5. Test monthly/annual UTC expiry, renewals, existing scholarships and trials.
-- 6. Add cancel/change-plan, refunds/disputes handling and verified receipts.
-- 7. Never describe manual payments as automatically renewing.
