-- ============================================================
--  One-time cleanup: remove leftover predictions stored under
--  names other than the five canonical players. This clears the
--  earlier duplicate rows (Unclearcactus, Señor Chang, Popsmoke)
--  so the leaderboard/reveal show each person only once.
--  Run in Supabase → SQL Editor.
-- ============================================================
delete from predictions
where player not in ('Champion', 'Cactus', 'Chang', 'Lizard', 'Pop Smoke');

-- Sanity check — should return exactly the five names.
select player, count(*) as picks
from predictions
group by player
order by player;
