# Scheduled workflows start hours late

Both workflows with a `schedule:` trigger fire hours after their cron time, and
changing the cron minute does not help. Left as is on purpose (2026-09-26):
neither job needs to land at a particular hour. Nothing has been dropped yet.

## What we measured

| Workflow | Cron (UTC) | Run created | Late by |
|---|---|---|---|
| `server-drift.yml` | Mon 06:37 | 2026-09-14 13:15, 2026-09-21 13:15 | ~6h38m |
| `server-drift.yml` (on `0 6`) | Mon 06:00 | 2026-08-31 12:22, 2026-09-07 11:16 | 5h16m–6h22m |
| `contract-tests.yml` | daily 04:23 | 2026-09-12 … 09-26, 08:41–10:03 | 4h20m–5h40m |

`created_at == run_started_at` on every one of them: GitHub creates the run
late, the self-hosted runner picks it up within seconds. A `workflow_dispatch`
of the same workflow starts immediately. Moving `server-drift` from `:00` to
`:37` changed nothing, so the delay is the scheduler, not the top-of-hour rush.

The repo is public, created 2026-07-25; every scheduled run we have is after
the 2026-08-26 incident below, so there is no "before" to compare with.

## What others report

- [community #196910](https://github.com/orgs/community/discussions/196910)
  (May 2026) — drift grew from ~1h40m (2025) to 4h30m+. A GitHub staff member
  answered that it is deliberate load balancing ("scheduled drops have grown
  >30% in 2ish months") and that a fix is a roadmap item, not imminent.
- [community #207346](https://github.com/orgs/community/discussions/207346)
  (opened 2026-09-09) — 4–6 h late and runs dropped since 2026-08-26, public and
  private repos, same `created_at == run_started_at` signature. No staff answer;
  commenters suspect per-repo scheduler state broken by that incident and point
  to GitHub Support with run ids as the only way to get it reset.
- [community #201738](https://github.com/orgs/community/discussions/201738)
  (July 2026) — 8–14 h late, changing the minute did not help. The accepted
  answer (a user, not staff, undocumented) claims young Free-tier repos sit in a
  low-priority queue swept once or twice a day.
- GitHub's own docs only say `schedule` "can be delayed during periods of high
  loads" and that queued jobs "may be dropped".

## If it starts to matter

1. **External trigger** — the only workaround that bypasses the scheduler:
   a systemd timer on the runner host calling `gh workflow run <file>` at the
   cron time, keeping the `schedule:` entry as a fallback. Needs a fine-grained
   PAT with Actions write on this repo only, stored on that host — a new
   credential, so it needs an explicit yes first.
2. **GitHub Support ticket** with run ids and timestamps, e.g. `34848170695`
   and `35604464968` (server-drift), in case it is the per-repo state from
   #207346.

A dropped run is the signal to act: `server-drift` would then skip a week and
the next range would simply be larger, while `contract-tests` would miss a day.
