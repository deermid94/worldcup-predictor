-- ============================================================
--  Lock the ENTIRE Last 32 round NOW (2026-06-30).
--  The crew agreed to submit their full Last 32 bracket up front,
--  so picks for every 'LAST 32' game are frozen immediately —
--  no more inserts/updates, regardless of kickoff time.
--
--  Later rounds (Round of 16, QF, SF, Final) keep the normal
--  rolling lock: each game closes 2 hours before its own kickoff.
--
--  Enforced in all THREE places picks can be written:
--    1. save_picks() RPC  (the path the app actually uses)
--    2. RLS insert policy  (defence in depth)
--    3. RLS update policy
--
--  Run ONCE in Supabase → SQL Editor. Safe to re-run.
-- ============================================================

-- ---- 1. The save_picks RPC (app writes go through this) ------
create or replace function save_picks(p_name text, p_picks jsonb)
  returns int
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare
  rec jsonb;
  n   int := 0;
begin
  if p_name not in ('Champion','Cactus','Chang','Lizard','Pop Smoke') then
    return -1;                                   -- unknown / not an entrant
  end if;

  for rec in select value from jsonb_array_elements(p_picks)
  loop
    insert into predictions(player, match_id, pick, advance)
    select p_name,
           (rec->>'match_id')::bigint,
           rec->>'pick',
           nullif(rec->>'advance','')
    where exists (
      select 1 from matches m
      where m.id = (rec->>'match_id')::bigint
        and m.stage  not ilike 'Group%'              -- knockout only
        and m.stage  <> 'LAST 32'                    -- Last 32 fully locked now
        and m.kickoff > now() + interval '2 hours'   -- rolling 2h lock for later rounds
    )
    on conflict (player, match_id) do update
      set pick = excluded.pick, advance = excluded.advance;

    if found then n := n + 1; end if;            -- count only rows that passed
  end loop;

  return n;
end;
$$;

grant execute on function save_picks(text, jsonb) to anon;

-- ---- 2. RLS insert policy ------------------------------------
drop policy if exists "predictions insertable before kickoff" on predictions;
create policy "predictions insertable before kickoff" on predictions
  for insert with check (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.stage not ilike 'Group%'
        and m.stage <> 'LAST 32'
        and m.kickoff > now() + interval '2 hours'
    )
  );

-- ---- 3. RLS update policy ------------------------------------
drop policy if exists "predictions updatable before kickoff" on predictions;
create policy "predictions updatable before kickoff" on predictions
  for update using (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id and m.stage not ilike 'Group%'
        and m.stage <> 'LAST 32' and m.kickoff > now() + interval '2 hours'
    )
  ) with check (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id and m.stage not ilike 'Group%'
        and m.stage <> 'LAST 32' and m.kickoff > now() + interval '2 hours'
    )
  );

-- ---- Verify: try to save should now be rejected for Last 32 ----
-- These two policies should be listed (insert + update):
select policyname, cmd from pg_policies
where tablename = 'predictions' and policyname like '%before kickoff%';
