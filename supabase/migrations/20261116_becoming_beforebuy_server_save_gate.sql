-- Becoming: protect Before You Buy saves at the database function boundary.
-- Based on the live function definition inspected November 16, 2026.
-- Preserve its existing argument names, return shape, ownership checks,
-- optimistic concurrency, advisory lock, and all other free sections.
-- This migration does not alter or delete existing records.
begin;

create or replace function public.becoming_save_section(
  p_section text, p_content jsonb, p_expected jsonb, p_row_id uuid
)
returns table(record_id uuid)
language plpgsql
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_previous public.recovery_records%rowtype;
  v_count integer;
begin
  if v_user is null then
    raise exception 'You must sign in to save a record.';
  end if;
  if p_section is null or p_section not in (
    'checkins','reflections','goals','wins','plans','gratitudes',
    'journeys','personalTokens','favorites','copingTools','urgeLetters',
    'buyDecisions','overview_week','overview_month','overview_year'
  ) then
    raise exception 'Invalid recovery section.';
  end if;
  if p_content is null or pg_catalog.jsonb_typeof(p_content) <> 'array' then
    raise exception 'Invalid record content.';
  end if;

  -- Only the structured Before You Buy decision writer requires Premium.
  -- A member can still read/export existing decisions through their own
  -- recovery_records SELECT policy. Their other free sections are untouched.
  if p_section = 'buyDecisions'
     and not public.becoming_has_premium_access() then
    raise exception 'Premium membership or an active trial is required to save Before You Buy decisions.'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text || ':' || p_section, 0)
  );
  select count(*) into v_count
    from public.recovery_records
    where user_id = v_user and section = p_section;
  if v_count > 1 then
    raise exception 'Multiple rows were found for this section. No changes saved; export a backup and review the duplicate records.';
  end if;
  if p_row_id is null then
    if p_expected is not null then
      raise exception 'Record baseline mismatch. No changes saved.';
    end if;
    if v_count = 1 then
      select * into v_previous from public.recovery_records
        where user_id = v_user and section = p_section;
      if v_previous.content = p_content then
        record_id := v_previous.id;
        return next;
        return;
      end if;
      raise exception 'Conflict: another device already saved this section. Nothing was overwritten.';
    end if;
    insert into public.recovery_records(user_id, section, content)
      values (v_user, p_section, p_content)
      returning id into v_id;
  else
    if p_expected is null then
      raise exception 'Missing original record. Nothing saved.';
    end if;
    update public.recovery_records
      set content = p_content
      where id = p_row_id and user_id = v_user and section = p_section
        and content = p_expected
      returning id into v_id;
    if v_id is null then
      select * into v_previous from public.recovery_records
        where id = p_row_id and user_id = v_user and section = p_section;
      if found and v_previous.content = p_content then
        record_id := v_previous.id;
        return next;
        return;
      end if;
      raise exception 'Conflict: this section changed on another device. Nothing was overwritten.';
    end if;
  end if;
  record_id := v_id;
  return next;
end;
$function$;

commit;

-- Important follow-up before release:
-- Verify direct INSERT/UPDATE/DELETE on recovery_records are disallowed
-- to authenticated clients, or Premium users could bypass this RPC.
-- Also test direct RPC attempts with non-Premium and Premium accounts.
-- Already saved decisions remain readable; modifying/deleting them through
-- this RPC requires Premium. Backup restore of that section is also gated.
