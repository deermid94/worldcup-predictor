#!/usr/bin/env python3
"""
Generate load-group-picks.sql from the picks spreadsheet.

- Reads the .xlsx board (fixtures across columns, one player per row).
- Pulls the real group fixtures (id, home, away) from Supabase.
- Maps each player's picked team -> Home/Draw/Away for that fixture.
- Self-checks against the already-played results (the sheet's own
  per-match points) and prints any disagreement.
- Writes load-group-picks.sql (gitignored) to run in the SQL editor.

Run:  python3 scripts/gen-picks.py
"""
import json, re, sys, unicodedata, urllib.request

XLSX  = "Championodeworld's World Cup Board 2026.xlsx"
SB     = "https://anqaowafgfjezzixnhgm.supabase.co"
ANON   = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6"
          "ImFucWFvd2FmZ2ZqZXp6aXhuaGdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MTQ5MTQs"
          "ImV4cCI6MjA5NzI5MDkxNH0.ldYd7cr94Ksv2egajajVjgbG2scdNfwLFCTndK5gj2Y")

# sheet row label -> display name used everywhere in the app/db
PLAYERS = {
    "Champion": "Champion",
    "Unclearcactus": "Cactus",
    "Señor Chang": "Chang",
    "Lizard": "Lizard",
    "Popsmoke": "Pop Smoke",
}

# alias a messy/variant team name (post-normalisation) to its canonical key
ALIASES = {
    "czech republic": "czechia", "chechia": "czechia", "czech": "czechia",
    "usa": "united states", "us": "united states",
    "dr congo": "congo dr",
    "holland": "netherlands",
    "swiss": "switzerland",
    "equador": "ecuador",
    "columbia": "colombia",
    "cape verde": "cape verde islands",
    "bosnia": "bosnia herzegovina",
    "bosnia herzegovina": "bosnia herzegovina",
    "spin": "spain",
    "bbrazil": "brazil",
    "bbelguim": "belgium", "belguim": "belgium",
    "ivory coast": "ivory coast",
}

def norm(s):
    if s is None: return ""
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()
    s = s.lower().replace("&", " ").replace("-", " ")
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return ALIASES.get(s, s)

def fetch_matches():
    req = urllib.request.Request(
        f"{SB}/rest/v1/matches?select=id,stage,home_team,away_team,home_score,away_score&order=kickoff",
        headers={"apikey": ANON})
    return json.load(urllib.request.urlopen(req))

def main():
    import openpyxl
    wb = openpyxl.load_workbook(XLSX, data_only=True)
    ws = wb.worksheets[0]
    rows = [[c for c in r] for r in ws.iter_rows(values_only=True)]

    # locate rows by content (the board has a blank leading row, etc.)
    def vs_count(r): return sum(1 for c in r if c and re.search(r"\svs?\s", str(c).lower()))
    fixtures_row = max(rows, key=vs_count)
    player_rows = {}
    for r in rows:
        label = (str(r[0]).strip() if r and r[0] else "")
        if label in PLAYERS:
            player_rows[PLAYERS[label]] = r
    missing = set(PLAYERS.values()) - set(player_rows)
    if missing:
        print("!! could not find player rows for:", missing); sys.exit(1)

    matches = fetch_matches()
    groups = [m for m in matches if (m["stage"] or "").lower().startswith("group")]
    # index group fixtures by unordered normalised team pair
    by_pair = {}
    for m in groups:
        key = frozenset((norm(m["home_team"]), norm(m["away_team"])))
        by_pair[key] = m

    def outcome(m):
        h, a = m["home_score"], m["away_score"]
        if h is None or a is None: return None
        return "H" if h > a else "A" if a > h else "D"

    def pick_code(m, picked):
        p = norm(picked)
        if p in ("draw", "draws", ""): return "D" if p else None
        # Lizard sometimes wrote the column letter: "a" = home team, "b" = away team
        if p == "a": return "H"
        if p == "b": return "A"
        if p == norm(m["home_team"]): return "H"
        if p == norm(m["away_team"]): return "A"
        return None  # unknown team name

    out_rows = []        # (player, match_id, code)
    unmatched_fix = []   # sheet fixtures we couldn't tie to a DB group match
    unmatched_pick = []  # picks whose team didn't match either side
    check_fail = []      # derived correctness != sheet's recorded points

    ncol = len(fixtures_row)
    for col in range(1, ncol, 4):           # blocks start at col B (index 1), width 4
        fx = fixtures_row[col]
        if not fx or not re.search(r"\svs?\s", str(fx).lower()):
            continue
        teams = re.split(r"\s+vs?\s+", re.sub(r"\(.*?\)", "", str(fx)).strip(), flags=re.I)
        if len(teams) != 2:
            continue
        key = frozenset((norm(teams[0]), norm(teams[1])))
        m = by_pair.get(key)
        if not m:                            # knockout placeholder or unknown — skip
            unmatched_fix.append(str(fx).strip())
            continue
        res = outcome(m)
        for player, r in player_rows.items():
            picked = r[col]
            if picked is None or str(picked).strip() == "":
                continue
            code = pick_code(m, picked)
            if code is None:
                unmatched_pick.append((player, str(fx).strip(), str(picked).strip()))
                continue
            out_rows.append((player, m["id"], code))
            # self-check vs the sheet's own per-match points (col+2), only for played games
            if res is not None:
                sheet_pts = r[col + 2]
                try: sheet_pts = float(sheet_pts) if sheet_pts not in (None, "") else None
                except (TypeError, ValueError): sheet_pts = None
                if sheet_pts is not None:
                    derived = 1.0 if code == res else 0.0
                    if derived != sheet_pts:
                        check_fail.append((player, str(fx).strip(),
                                           str(picked).strip(), code, res, sheet_pts))

    # ---- report ----
    print(f"Group fixtures in DB: {len(groups)}")
    print(f"Pick rows generated:  {len(out_rows)}")
    print(f"Played games checked against sheet points; disagreements: {len(check_fail)}")
    if unmatched_fix:
        uf = sorted(set(unmatched_fix))
        print(f"\nSkipped {len(uf)} non-group/unmatched fixtures (expected: knockouts):")
        for f in uf[:8]: print("   -", f)
        if len(uf) > 8: print(f"   … and {len(uf)-8} more")
    if unmatched_pick:
        print(f"\n** {len(unmatched_pick)} picks skipped — team name not recognised "
              f"(no pick loaded for that player/game):")
        for p in unmatched_pick: print("   ", p)
    if check_fail:
        print("\n!! self-check mismatches (derived result != sheet points):")
        for c in check_fail: print("   ", c)

    if check_fail:
        print("\nNOT writing SQL — self-check failed, investigate above.")
        sys.exit(2)

    # ---- emit SQL ----
    def esc(s): return s.replace("'", "''")
    lines = [
        "-- ============================================================",
        "--  GENERATED — do not edit by hand. Group-stage picks.",
        "--  Run in Supabase SQL Editor AFTER auth-and-lock.sql.",
        "--  Loads here bypass row-level security (postgres role).",
        "-- ============================================================",
        "insert into predictions (player, match_id, pick) values",
    ]
    vals = [f"  ('{esc(p)}', {mid}, '{code}')" for (p, mid, code) in out_rows]
    lines.append(",\n".join(vals))
    lines.append("on conflict (player, match_id) do update set pick = excluded.pick;")
    with open("load-group-picks.sql", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\n✓ Wrote load-group-picks.sql ({len(out_rows)} picks).")

if __name__ == "__main__":
    main()
