defmodule SanbaseWeb.Admin.Stats do
  @moduledoc """
  Aggregated counts shown on the admin home page. The full payload is
  computed once and cached for `@ttl_seconds` to avoid hammering the DB
  on every page load.
  """

  import Ecto.Query

  alias Sanbase.Repo

  @ttl_seconds 900
  @series_days 14

  @spec get() :: map()
  def get do
    cache_key = {__MODULE__, :get, :v7} |> Sanbase.Cache.hash()

    case Sanbase.Cache.get_or_store({cache_key, @ttl_seconds}, fn -> {:ok, compute()} end) do
      {:ok, stats} -> stats
      _ -> compute()
    end
  end

  defp compute do
    now = DateTime.utc_now()
    day_ago = DateTime.add(now, -1, :day)
    week_ago = DateTime.add(now, -7, :day)
    today = DateTime.to_date(now)
    series_start = Date.add(today, -(@series_days - 1))

    parts =
      [
        series: fn -> series_block(series_start, today) end,
        users: fn -> users_block(day_ago, week_ago) end,
        metric_registry: fn -> metric_registry_block() end,
        promo_trials: fn -> promo_trials_block(week_ago) end,
        subscriptions: &active_subscriptions_by_product/0,
        faq_entries: &faq_entries_block/0,
        disagreement_tweets: &disagreement_tweets_block/0,
        insights: fn -> %{total: count(Sanbase.Insight.Post)} end,
        comments: fn -> %{total: count(Sanbase.Comment)} end,
        oban: fn -> oban_by_queue(day_ago, week_ago) end
      ]
      |> Task.async_stream(
        fn {key, fun} -> {key, fun.()} end,
        max_concurrency: 8,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, kv} -> kv end)
      |> Map.new()

    Map.put(parts, :computed_at, now)
  end

  defp users_block(day_ago, week_ago) do
    from(u in Sanbase.Accounts.User,
      select: %{
        total: count(u.id),
        last_24h: count(fragment("CASE WHEN ? >= ? THEN 1 END", u.inserted_at, ^day_ago)),
        last_7d: count(fragment("CASE WHEN ? >= ? THEN 1 END", u.inserted_at, ^week_ago))
      }
    )
    |> Repo.one()
  end

  defp metric_registry_block do
    base =
      from(r in Sanbase.Metric.Registry,
        select: %{
          total: count(r.id),
          not_synced: count(fragment("CASE WHEN ? = 'not_synced' THEN 1 END", r.sync_status)),
          unverified: count(fragment("CASE WHEN ? = false THEN 1 END", r.is_verified)),
          deprecated: count(fragment("CASE WHEN ? = true THEN 1 END", r.is_deprecated))
        }
      )
      |> Repo.one()

    pending_approval =
      count(
        from(s in Sanbase.Metric.Registry.ChangeSuggestion,
          where: s.status == "pending_approval"
        )
      )

    Map.put(base, :pending_approval, pending_approval)
  end

  defp promo_trials_block(week_ago) do
    %{
      last_7d:
        count(
          from(p in Sanbase.Billing.Subscription.PromoTrial,
            where: p.inserted_at >= ^week_ago
          )
        )
    }
  end

  defp faq_entries_block do
    from(f in Sanbase.Knowledge.FaqEntry,
      select: %{
        active: count(fragment("CASE WHEN ? = false THEN 1 END", f.is_deleted)),
        deleted: count(fragment("CASE WHEN ? = true THEN 1 END", f.is_deleted))
      }
    )
    |> Repo.one()
  end

  defp disagreement_tweets_block do
    from(t in Sanbase.DisagreementTweets.ClassifiedTweet,
      select: %{
        total: count(t.id),
        review_required: count(fragment("CASE WHEN ? = true THEN 1 END", t.review_required))
      }
    )
    |> Repo.one()
  end

  defp series_block(series_start, today) do
    schemas = [
      users: {Sanbase.Accounts.User, :inserted_at},
      watchlists: {Sanbase.UserList, :inserted_at},
      chart_configurations: {Sanbase.Chart.Configuration, :inserted_at},
      alerts: {Sanbase.Alert.UserTrigger, :inserted_at},
      alerts_fired: {Sanbase.Alert.HistoricalActivity, :triggered_at},
      insights: {Sanbase.Insight.Post, :inserted_at},
      comments: {Sanbase.Comment, :inserted_at},
      promo_trials: {Sanbase.Billing.Subscription.PromoTrial, :inserted_at}
    ]

    rows =
      schemas
      |> Task.async_stream(
        fn {key, {schema, field}} -> {key, daily_counts(schema, series_start, field)} end,
        max_concurrency: 8,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, kv} -> kv end)
      |> Map.new()

    Map.merge(rows, %{days: @series_days, start_date: series_start, end_date: today})
  end

  defp count(query), do: Repo.aggregate(query, :count)

  defp oban_by_queue(day_ago, week_ago) do
    scheduled_states = ["available", "scheduled", "retryable"]

    from(j in Oban.Job,
      where:
        j.state in ^scheduled_states or
          j.state == "executing" or
          (j.state == "completed" and j.completed_at >= ^week_ago) or
          (j.state == "discarded" and j.discarded_at >= ^week_ago) or
          (j.state == "cancelled" and j.cancelled_at >= ^week_ago),
      group_by: j.queue,
      select: %{
        queue: j.queue,
        scheduled: count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", j.state, ^scheduled_states)),
        executing: count(fragment("CASE WHEN ? = 'executing' THEN 1 END", j.state)),
        completed_1d:
          count(
            fragment(
              "CASE WHEN ? = 'completed' AND ? >= ? THEN 1 END",
              j.state,
              j.completed_at,
              ^day_ago
            )
          ),
        completed_7d:
          count(
            fragment(
              "CASE WHEN ? = 'completed' AND ? >= ? THEN 1 END",
              j.state,
              j.completed_at,
              ^week_ago
            )
          ),
        discarded_7d:
          count(
            fragment(
              "CASE WHEN ? = 'discarded' AND ? >= ? THEN 1 END",
              j.state,
              j.discarded_at,
              ^week_ago
            )
          ),
        cancelled_7d:
          count(
            fragment(
              "CASE WHEN ? = 'cancelled' AND ? >= ? THEN 1 END",
              j.state,
              j.cancelled_at,
              ^week_ago
            )
          )
      },
      order_by: j.queue
    )
    |> Repo.all()
  end

  defp active_subscriptions_by_product do
    product_codes = ["SANBASE", "SANAPI"]

    rows =
      from(s in Sanbase.Billing.Subscription,
        join: pl in assoc(s, :plan),
        join: pr in assoc(pl, :product),
        where:
          s.status in [:active, :trialing] and pl.name != "FREE" and
            pr.code in ^product_codes,
        group_by: [pr.code, pl.name],
        select: {pr.code, pl.name, count()}
      )
      |> Repo.all()

    by_product =
      rows
      |> Enum.group_by(fn {code, _, _} -> code end, fn {_, plan, c} -> {plan, c} end)
      |> Map.new(fn {code, plans} ->
        {code,
         %{
           total: Enum.reduce(plans, 0, fn {_, c}, acc -> acc + c end),
           by_plan: Enum.sort_by(plans, fn {_, c} -> -c end)
         }}
      end)

    sanbase = Map.get(by_product, "SANBASE", %{total: 0, by_plan: []})
    sanapi = Map.get(by_product, "SANAPI", %{total: 0, by_plan: []})

    %{
      total: by_product |> Map.values() |> Enum.reduce(0, &(&1.total + &2)),
      sanbase: sanbase,
      sanapi: sanapi
    }
  end

  defp daily_counts(schema, start_date, field) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00])

    rows =
      schema
      |> from(as: :r)
      |> where([r: r], field(r, ^field) >= ^start_dt)
      |> group_by(
        [r: r],
        fragment("date_trunc('day', ? AT TIME ZONE 'UTC')::date", field(r, ^field))
      )
      |> select(
        [r: r],
        {fragment("date_trunc('day', ? AT TIME ZONE 'UTC')::date", field(r, ^field)), count()}
      )
      |> Repo.all()
      |> Map.new()

    for offset <- 0..(@series_days - 1) do
      Map.get(rows, Date.add(start_date, offset), 0)
    end
  end
end
