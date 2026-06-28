-- ============================================================
--  Hardening before sharing: only the five real players may have
--  prediction rows. This blocks the public API from inserting junk
--  / fake / malicious player names (defence-in-depth with the
--  client-side escaping). Run in Supabase → SQL Editor.
--  Safe to re-run.
--
--  ALSO the authoritative insert/update rules for picks. If these
--  policies are missing, EVERY pick save is rejected with
--  "new row violates row-level security policy" — re-run this file.
-- ============================================================

-- Make sure row-level security is on (it's the layer these policies work in).
alter table predictions enable row level security;

-- Re-create the insert policy: picks lock 2 HOURS before kickoff, not a
-- group game, AND the player must be one of the known entrants.
drop policy if exists "predictions insertable before kickoff" on predictions;
create policy "predictions insertable before kickoff" on predictions
  for insert with check (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.kickoff > now() + interval '2 hours'
        and m.stage not ilike 'Group%'
    )
  );

-- Same guard on updates.
drop policy if exists "predictions updatable before kickoff" on predictions;
create policy "predictions updatable before kickoff" on predictions
  for update using (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id and m.kickoff > now() + interval '2 hours' and m.stage not ilike 'Group%'
    )
  ) with check (
    player in ('Champion','Cactus','Chang','Lizard','Pop Smoke')
    and exists (
      select 1 from matches m
      where m.id = match_id and m.kickoff > now() + interval '2 hours' and m.stage not ilike 'Group%'
    )
  );

-- ---- Verify: this should list BOTH policies after running ------
-- (one for insert, one for update). If it returns 0 rows, the
-- create statements above didn't run — scroll up for an error.
select policyname, cmd from pg_policies
where tablename = 'predictions' and policyname like '%before kickoff%';
