# CMC Pro Backfill Runbook

## Dry run for one asset

```elixir
slug = "bitcoin"

{:ok, precheck} =
  Sanbase.ExternalServices.Coinmarketcap.ProBackfill.gap_check(
    scope: :single,
    slug: slug,
    interval: "5m"
  )

from = precheck.recommended_time_start
to = precheck.recommended_time_end

{:ok, run} =
  Sanbase.ExternalServices.Coinmarketcap.ProBackfill.start_run(
    scope: :single,
    slug: slug,
    time_start: from,
    time_end: to,
    interval: "5m",
    dry_run?: true
  )
```

## Verify dry run

```elixir
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.status(run.id)

Sanbase.ExternalServices.Coinmarketcap.ProBackfill.gap_check(
  scope: :single,
  slug: slug,
  interval: "5m"
)
```

## Actual run for one asset

```elixir
{:ok, run} =
  Sanbase.ExternalServices.Coinmarketcap.ProBackfill.start_run(
    scope: :single,
    slug: slug,
    time_start: from,
    time_end: to,
    interval: "5m"
  )
```

## Actual run for all assets

```elixir
{:ok, run} =
  Sanbase.ExternalServices.Coinmarketcap.ProBackfill.start_run(
    scope: :all,
    time_start: from,
    time_end: to,
    interval: "5m"
  )
```

## Progress and controls

```elixir
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.status(run.id)
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.pause_run(run.id)
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.resume_run(run.id)
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.cancel_run(run.id)
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.list_runs(limit: 20)
Sanbase.ExternalServices.Coinmarketcap.ProBackfill.AuditReport.run_report(run.id)
```

## Final verification

Run the same gap check for the completed interval and ensure:

- `has_gap` is false for fillable ranges
- run status is `completed`
- `failed_assets` is zero or only contains expected deferred ranges
