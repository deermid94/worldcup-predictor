# World Cup 2026 Predictor — Setup (fully automatic)

A website where you + your friends predict match results (Home win / Draw / Away win).

- **Nobody can see anyone else's pick until that game kicks off** (enforced by the database).
- **Fixtures and scores update themselves** — a robot pulls them from a football data
  service every 15 minutes, so games that finish at 3am Irish time are scored by morning.

You set this up once (~20 min). Everything is free. You'll create **3 free accounts**:
Supabase (database), football-data.org (scores), and GitHub (hosting + the robot).

---

## Part A — Database (Supabase)

1. **https://supabase.com** → sign up → **New project**. Name it `worldcup`, set a database
   password (save it), pick the nearest region, **Create**. Wait ~2 min.
2. Left sidebar → **SQL Editor** → **New query**. Open `schema.sql` from this folder, copy
   it all, paste, **Run**. You should see "Success".
3. Left sidebar → **Project Settings** (gear) → **API**. Keep this tab open — you'll copy
   three things from here:
   - **Project URL** (e.g. `https://abcd1234.supabase.co`)
   - **anon public** key (goes in the webpage — safe to share)
   - **service_role** key (SECRET — goes only into GitHub, never in the page)

4. Paste the first two into `index.html`. Open it in a text editor, find near the top of
   the `<script>`:
   ```js
   const SUPABASE_URL      = 'YOUR_PROJECT_URL';
   const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
   ```
   Fill in the **Project URL** and the **anon public** key. Save.

## Part B — Scores data source (football-data.org)

1. **https://www.football-data.org/client/register** → register for the **free** tier.
2. They email you an **API token**. Copy it — it goes into GitHub in Part C.

> The free tier covers the FIFA World Cup. If you ever see the robot log a "403 / not
> available on your plan" error, tell me and I'll switch the source to an alternative.

## Part C — Hosting + the robot (GitHub)

1. **https://github.com** → sign up (if needed) → create a **New repository**, e.g.
   `worldcup-predictor`. Make it **Public** (needed for free GitHub Pages).
2. Upload this whole folder's contents to the repo (drag the files onto the repo page, or
   I can push them for you — just ask). Make sure these come along:
   - `index.html`
   - `scripts/sync.mjs`
   - `.github/workflows/update.yml`
3. **Add the secrets** the robot needs. Repo → **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**. Add three:
   | Name | Value |
   |------|-------|
   | `FOOTBALL_DATA_KEY` | your football-data.org token (Part B) |
   | `SUPABASE_URL` | your Supabase Project URL |
   | `SUPABASE_SERVICE_KEY` | your Supabase **service_role** key |
4. **Turn on the robot now (first run).** Repo → **Actions** tab → if prompted, enable
   workflows → click **"Sync World Cup fixtures & scores"** → **Run workflow**. It pulls all
   fixtures into your database. After this it runs itself every 15 minutes.
5. **Turn on hosting.** Repo → **Settings** → **Pages** → under "Build and deployment",
   Source = **Deploy from a branch**, Branch = **main** / root → **Save**. After a minute
   you get a public link like `https://yourname.github.io/worldcup-predictor/`.

## Part D — Play

Send the GitHub Pages link to your 4 friends. Each person opens it, enters a nickname,
and picks results for upcoming games. That's it — you never touch fixtures or scores again.

---

## What's automatic vs. manual

| Thing | Who does it |
|-------|-------------|
| Loading the fixture list | 🤖 robot |
| Locking picks at kickoff | 🤖 database |
| Hiding picks until kickoff | 🤖 database |
| Entering final scores | 🤖 robot |
| Updating the leaderboard | 🤖 page (from scores) |
| Making predictions | 🧑 you + friends |

## Good to know / limits

- **Nickname login is honour-system** (no password) — fine for 5 friends. The protected
  part — no one sees another's pick before kickoff — is properly enforced.
- **Your own picks are remembered per-device** (the DB hides picks before kickoff, even
  from you, so the page shows your pending picks from this browser). Switch device before
  kickoff → re-enter them.
- **Knockout games decided on penalties:** scores are recorded as the full-time result, so
  a game level after extra time shows as a Draw. If you want penalty winners to count as a
  Win for that side, tell me and I'll adjust the scoring.
- **The robot runs every 15 min.** Final scores usually appear within ~15–30 min of the
  final whistle. You can force an immediate update anytime via Actions → Run workflow.
- All three services are free for this scale; no credit card needed.
