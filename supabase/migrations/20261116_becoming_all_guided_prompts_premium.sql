-- Consolidates ALL guided prompts as Premium; plain free writing stays free.
-- Previously saved reflections and their prompt text are NOT modified.
begin;
create or replace function public.becoming_premium_reflection_prompts()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
 if (select auth.uid()) is null then raise exception 'Sign in required' using errcode = '42501'; end if;
 if not public.becoming_has_premium_access() then raise exception 'Premium membership required' using errcode = '42501'; end if;
 return jsonb_build_array(
    jsonb_build_object('category','Daily Check-In','prompt','What feelings have been coming up for me today?'),
    jsonb_build_object('category','Money & Emotions','prompt','What stirred an urge to spend, and what did I need in that moment?'),
    jsonb_build_object('category','Grounding','prompt','What helped me feel safe or grounded today?'),
    jsonb_build_object('category','Self-Compassion','prompt','When did I choose something kind for myself?'),
    jsonb_build_object('category','Spending Triggers','prompt','What did I learn about my spending triggers?'),
    jsonb_build_object('category','Small Victories','prompt','What is one small win I want to remember?'),
    jsonb_build_object('category','Support','prompt','What would support look like for me tomorrow?'),
    jsonb_build_object('category','Letting Go','prompt','What am I carrying that I can put down for tonight?'),
    jsonb_build_object('category','Boundaries','prompt','How did I honor a personal boundary today?'),
    jsonb_build_object('category','Peace','prompt','What brought me even a moment of peace?'),
    jsonb_build_object('category','Self-Trust','prompt','What is one decision I made that I can learn to trust myself about, even if it was imperfect?'),
    jsonb_build_object('category','Boundaries','prompt','Where have I said yes when I needed space, and what could a kind boundary look like?'),
    jsonb_build_object('category','Money & Emotions','prompt','What feeling am I hoping a purchase might change, and what else could help me tend to that feeling?'),
    jsonb_build_object('category','Inner Safety','prompt','What helps me feel steady when life is uncertain, and how could I make room for more of it?'),
    jsonb_build_object('category','Personal Growth','prompt','What parts of myself am I rediscovering beyond the roles I have played for other people?'),
    jsonb_build_object('category','Hope & Becoming','prompt','What would I tell a future version of myself about the courage it took to reach today?')
 );
end;
$$;
revoke all on function public.becoming_premium_reflection_prompts() from public,anon;
grant execute on function public.becoming_premium_reflection_prompts() to authenticated;
commit;
