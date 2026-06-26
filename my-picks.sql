-- ============================================================
--  World Cup 2026 Predictor — let a player see their OWN picks
--  before kickoff (a private reminder). Run ONCE in Supabase:
--  dashboard → SQL Editor → paste → Run. Safe to re-run.
-- ============================================================

-- Returns a player's own predictions, but ONLY when their PIN checks out.
-- SECURITY DEFINER so it can read past the row-level-security rule that
-- normally hides predictions until kickoff — yet it only ever returns rows
-- for the PIN-verified caller, so nobody can peek at anyone else's picks.
create or replace function my_predictions(p_name text, p_pin text)
  returns table(match_id bigint, pick text)
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
    select pr.match_id, pr.pick from predictions pr where pr.player = p_name;
end;
$$;

grant execute on function my_predictions(text, text) to anon;
