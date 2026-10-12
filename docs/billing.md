# Billing — what the app does with cost centers, and why

Billing is a server switch (`billing_enabled`, read from `/settings/ui-flags`, else
`/settings` — `billingEnabledProvider`). With it on, **every queue create, edit and
start needs a `cost_center_id`** (`services/finance_budget.py::validate_print_budget`),
and the server works the job's cost out itself: the `estimated_cost` a client sends is
a display hint it ignores. The reference for what each route accepts is `routes/finance.py`.

## The print form

`QueueEditScreen` offers the cost center select whenever billing is on and there is
something to pick (`printableCostCentersProvider`, from `GET /finance/cost-centers/mine`,
filtered to active and `can_print` as the web does; the user's private center is the
default). What the form does is decided by one step per build (`_CostCenterStep`):

| Step | Meaning | Save |
|---|---|---|
| `unknown` | flags (and, before 1.2.6, the settings) have not said | waits, for a job that needs a center |
| `off` | no billing | as ever |
| `loading` / `failed` | the list is being read / could not be | waits / retry |
| `pick` | something to choose | sends the pick |
| `none` | the user may print to no active center | blocked: an administrator has to grant one |
| `refused` | the session may not list centers | blocked: only the browser gets around it |

`refused` is **not** `none`. An API key on a server before maziggy/bambuddy#3256 is
answered 401 (the permission checks hand a key no user), and so is a server with
authentication off; the words differ because the remedies do. A password login's 401 is
a lost session and stays an error.

Under the select the form previews the job's cost and warns when it is more than the
center has left (`jobCostProvider`, `estimateJobCost`), as the web's mapping panel does:
each filament's grams at the price of the spool on the tray it is mapped to, else at
`default_filament_cost`, times the copies. It needs a mapping, so a job for "any printer of
a model" has no preview, and with Spoolman every job is priced at the default, which is
all the server uses there. It is only a preview — the server prices the job itself and
refuses it when it does not fit; a contract test keeps the two within a cent.

A job that already has a center is never blocked by any of this: the server keeps the
stored center on a PATCH that omits it. `_costCenterRequired` is "a new job, or one
queued before billing".

## Where a job cannot get a center

- **The library's bulk "Add to queue" and "queue as alternatives"** call routes that
  take no center (`AddToQueueRequest`, `variants`), so on a billing server they stop
  with `queueBillingNoBulk`. One file opens the print form instead.
- **Dispatching more runs of an order** (`POST /queue/batches/{id}/dispatch`) clones
  the source item without `cost_center_id` — `CLONED_SETTING_COLUMNS` in
  `services/print_batch.py` leaves it out — so on a billing server the new runs fail at
  the scheduler. Measured on a `daily` image; a server defect, not worked around here.

## The Finance screen

`/finance`, in the drawer only where billing is on **and** `identifiedPermissionProvider`
holds `cost_centers:read_own` — no API key can hold it, so a key session never sees the
entry. Personal view: balance, the user's centers with what is left of each budget, and
their own ledger (paged, 50 a page). Whoever holds any of `read_all`, `create`, `modify`
also gets the admin view, and what it shows follows the permission: every center and
every user's ledger need `read_all` (without it the ledger stays the user's own), creating
a center needs `create`, and every other write — budgets, members, wallet, manual
charges, editing or deleting a row — needs `modify`, wherever the row came from.

Rules the screen follows because the server does:

- A **private center** takes a budget and nothing else: rename, deactivate, delete and
  any membership change answer 400. Its menu offers Edit alone, and its edit form locks
  the name. A budget of 0 is how it is stopped from printing.
- A budget is **one figure of one kind**; a monthly one wins over a total, and a body
  naming neither removes the budget (`update_cost_center_budgets`).
- A center a non-voided ledger row names, or an active budget hold, **cannot be
  deleted**; both refusals are worded in `finance_forms.dart`.
- A ledger edit sends only what changed (the server stamps any description it is sent
  as an admin edit) and cannot take a row off its center — the web cannot either.
- Filters narrow the loaded rows; the endpoint filters on neither, so an empty result
  is not proof that nothing matches further down.

`DemoFinance` (`lib/core/demo/demo_finance.dart`) serves all of it as state, and
`test/contract/ws_billing_contract_test.dart` runs the same flows against a real server
(the stack is in `tool/ci/`; run it on `daily` **and** `latest`).
