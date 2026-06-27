-- ============================================================
--  World Cup 2026 Predictor — knockout scoring (2 points)
--  Run ONCE in Supabase: dashboard → SQL Editor → paste → Run.
--  Safe to re-run (idempotent).
--
--  Knockout games are worth 2 points:
--    • 1 pt — correct full-time (90-minute) result: Home / Draw / Away
--    • 1 pt — correct team to progress
--  If a game goes to extra time or penalties, the 90-minute result was
--  by definition a DRAW — so for scoring we only need the feed's
--  duration (REGULAR vs ET/PENS) and the ultimate winner.
-- ============================================================

-- ---- matches: how a knockout game was decided -------------------
-- winner  : 'H' or 'A' — the team that ultimately progressed (null for
--           draws/groups or games not yet finished).
-- duration: 'REGULAR' | 'EXTRA_TIME' | 'PENALTY_SHOOTOUT' from the feed.
--           ET/PENS ⇒ the 90-minute result was a draw.
alter table matches add column if not exists winner   text
  check (winner in ('H','A'));
alter table matches add column if not exists duration text;

-- ---- predictions: the "who progresses" pick --------------------
-- advance: 'H' or 'A' — the team the player thinks goes through.
-- For a Home/Away FT pick this equals that side; it's only an
-- independent choice when the player picks a Draw. Null for group games.
alter table predictions add column if not exists advance text
  check (advance in ('H','A'));

-- ---- let a player still see their OWN picks (now incl. advance) -
-- Recreated to return the advance column too. SECURITY DEFINER so it
-- reads past the hide-until-kickoff rule, but only for the PIN-verified
-- caller — nobody can peek at anyone else's picks.
drop function if exists my_predictions(text, text);
create or replace function my_predictions(p_name text, p_pin text)
  returns table(match_id bigint, pick text, advance text)
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare h text;
begin
  select pin_hash into h from players where name = p_name;
  if h is null then return; end if;            -- unknown / unclaimed player
  if h <> crypt(p_pin, h) then return; end if;  -- wrong PIN → return nothing
  return query
    select pr.match_id, pr.pick, pr.advance from predictions pr where pr.player = p_name;
end;
$$;

grant execute on function my_predictions(text, text) to anon;
