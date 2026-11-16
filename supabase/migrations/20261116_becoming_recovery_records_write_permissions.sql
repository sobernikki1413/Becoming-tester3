-- Becoming: close direct-table write bypass while preserving authenticated safe saves.
-- Run after 20261116_becoming_beforebuy_server_save_gate.sql.
-- No records, user memberships, or free sections are modified by this migration.
--
-- IMPORTANT: The existing becoming_save_section() is SECURITY INVOKER.
-- Simply revoking table writes would break ALL saves. Convert that function
-- to SECURITY DEFINER first, retaining its established auth.uid ownership,
-- allowlist, optimistic concurrency and Premium checks.
begin;

alter function public.becoming_save_section(text,jsonb,jsonb,uuid)
  security definer;

-- Keep function executable only by signed-in accounts. The function itself
-- resolves auth.uid() and limits all reads/writes to that member's records.
revoke all on function public.becoming_save_section(text,jsonb,jsonb,uuid)
  from public, anon;
grant execute on function public.becoming_save_section(text,jsonb,jsonb,uuid)
  to authenticated;

-- Deny direct member writes, including bypass attempts using REST.
-- Preserve SELECT privileges and owner-scoped read policies so members
-- can continue to view/export previously saved entries.
revoke insert, update, delete
  on table public.recovery_records from authenticated, anon, public;

commit;

-- Validation after installation:
-- SELECT
--   has_table_privilege('authenticated','public.recovery_records','INSERT') AS can_insert,
--   has_table_privilege('authenticated','public.recovery_records','UPDATE') AS can_update,
--   has_table_privilege('authenticated','public.recovery_records','DELETE') AS can_delete,
--   has_function_privilege('authenticated','public.becoming_save_section(text,jsonb,jsonb,uuid)','EXECUTE') AS can_safe_save;
-- Expected: false, false, false, true.
--
-- Still test actual authenticated safe-save of a harmless free entry,
-- non-Premium rejection for buyDecisions and two-account isolation.
-- Function runs with its database owner's privileges; never expose
-- arbitrary SQL, user IDs, or extra sections as parameters.
