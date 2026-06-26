-- ============================================================
--  World Cup 2026 Predictor — reveal ALL group-stage picks
--  Run ONCE in Supabase: dashboard → SQL Editor → paste → Run.
--  Safe to re-run (idempotent).
--
--  Group picks are LOCKED (auth-and-lock.sql blocks any insert/
--  update on 'Group%' matches from the website), so there is no
--  competitive reason to hide the group games that haven't kicked
--  off yet — nobody can change their group picks anyway. This makes
--  every group pick visible to everyone immediately. Knockout picks
--  stay hidden until their own kickoff, exactly as before.
-- ============================================================

drop policy if exists "predictions visible after kickoff" on predictions;
create policy "predictions visible after kickoff" on predictions
  for select using (
    exists (
      select 1 from matches m
      where m.id = match_id
        and (m.kickoff <= now() or m.stage ilike 'Group%')
    )
  );
