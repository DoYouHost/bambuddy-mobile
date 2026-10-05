# Scheduled workflows are dispatched by Dagu

`server-drift.yml` and `contract-tests.yml` have no `schedule:` trigger. They
are started through `workflow_dispatch` by [Dagu](https://github.com/dagu-org/dagu)
on `lxc-dagu` (`http://lxc-dagu.lan:8080`, an LXC on `pv1-rpi4` defined in
TofuSkierkiV2 `lxc_dagu.tf`). GitHub's own scheduler started them 4–8 hours
late and, on 2026-10-05, not at all (see below).

| DAG | Workflow | When (UTC) |
|---|---|---|
| `bambuddy-server-drift` | `server-drift.yml` | Mon 06:37 |
| `bambuddy-contract-tests` | `contract-tests.yml` | daily 04:23 |

## Configuration lives in the Dagu web UI

Tofu only builds the container and installs Dagu. The DAGs and the token are
set up in the UI and exist nowhere else:

- **DAGs**: one per workflow. A DAG is a single `http.request` step doing
  `POST https://api.github.com/repos/DoYouHost/bambuddy-mobile/actions/workflows/<file>/dispatches`
  with body `{"ref":"master"}` and headers `Authorization: Bearer ${GITHUB_TOKEN}`,
  `Accept: application/vnd.github+json`. To change a time, edit `schedule:`.
  "Start" runs the DAG immediately. A non-2xx answer fails the run.
- **Token**: Profiles → Secret Refs, a `dagu-managed` secret, which Dagu stores
  encrypted. The DAG reads it with
  `secrets: [{name: GITHUB_TOKEN, ref: <secret ref>}]`, which keeps it masked
  in the run history. A plain `env`/`dotenv` value would be stored in clear
  text in every run's status. The token is a fine-grained PAT owned by
  `DoYouHost`, scoped to the `bambuddy-mobile` repository only, with
  **Actions: read and write**. When it expires, the runs fail with 401. Use
  "Rotate Secret" to put in the new token.

## Why not `schedule:` (measured before the switch)

| Workflow | Cron (UTC) | Run created | Late by |
|---|---|---|---|
| `server-drift.yml` | Mon 06:37 | 2026-09-14 13:15, 2026-09-21 13:15, 2026-09-28 14:23 | 6h38m–7h46m |
| `server-drift.yml` (on `0 6`) | Mon 06:00 | 2026-08-31 12:22, 2026-09-07 11:16 | 5h16m–6h22m |
| `server-drift.yml` | Mon 06:37 | 2026-10-05: no run by 14:46 | 8h+ |
| `contract-tests.yml` | daily 04:23 | 2026-09-12 … 10-05, 08:41–11:38 | 4h20m–7h15m |

`created_at == run_started_at` on every one of them. GitHub created the run
late, and the self-hosted runner picked it up within seconds. Moving the minute
off `:00` changed nothing.

- [community #196910](https://github.com/orgs/community/discussions/196910):
  GitHub staff call it deliberate load balancing. A fix is on the roadmap,
  with no date.
- [community #207346](https://github.com/orgs/community/discussions/207346):
  runs 4–6 h late and dropped since 2026-08-26, with the same signature.
- GitHub's docs say only that `schedule` "can be delayed during periods of high
  loads" and that queued jobs "may be dropped".

A `schedule:` kept as a fallback would make every run a double, so there is none.
If `lxc-dagu` is down, nothing fires. Start the workflow by hand from the
Actions tab.
