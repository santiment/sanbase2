defmodule SanbaseWeb.Admin.Stats do
  @moduledoc """
  Aggregated counts shown on the admin home page. The full payload is
  computed once and cached for `@ttl_seconds` to avoid hammering the DB
  on every page load.
  """

  import Ecto.Query

  alias Sanbase.Repo

  @ttl_seconds 900

  @spec get() :: map()
  def get do
    cache_key = {__MODULE__, :get, :v4} |> Sanbase.Cache.hash()

    case Sanbase.Cache.get_or_store({cache_key, @ttl_seconds}, fn -> {:ok, compute()} end) do
      {:ok, stats} -> stats
      _ -> compute()
    end
  end

  @series_days 14

  defp compute do
    now = DateTime.utc_now()
    day_ago = DateTime.add(now, -1, :day)
    week_ago = DateTime.add(now, -7, :day)

    %{
      series: %{
        days: @series_days,
        users: daily_counts(Sanbase.Accounts.User),
        watchlists: daily_counts(Sanbase.UserList),
        chart_configurations: daily_counts(Sanbase.Chart.Configuration),
        alerts: daily_counts(Sanbase.Alert.UserTrigger),
        insights: daily_counts(Sanbase.Insight.Post),
        comments: daily_counts(Sanbase.Comment),
        promo_trials: daily_counts(Sanbase.Billing.Subscription.PromoTrial)
      },
      users: %{
        total: count(Sanbase.Accounts.User),
        last_24h: count(from(u in Sanbase.Accounts.User, where: u.inserted_at >= ^day_ago)),
        last_7d: count(from(u in Sanbase.Accounts.User, where: u.inserted_at >= ^week_ago))
      },
      metric_registry: %{
        total: count(Sanbase.Metric.Registry),
        not_synced:
          count(from(r in Sanbase.Metric.Registry, where: r.sync_status == "not_synced")),
        unverified: count(from(r in Sanbase.Metric.Registry, where: r.is_verified == false)),
        deprecated: count(from(r in Sanbase.Metric.Registry, where: r.is_deprecated == true)),
        pending_approval:
          count(
            from(s in Sanbase.Metric.Registry.ChangeSuggestion,
              where: s.status == "pending_approval"
            )
          )
      },
      promo_trials: %{
        last_7d:
          count(
            from(p in Sanbase.Billing.Subscription.PromoTrial,
              where: p.inserted_at >= ^week_ago
            )
          )
      },
      subscriptions: active_subscriptions_by_product(),
      faq_entries: %{
        active: count(from(f in Sanbase.Knowledge.FaqEntry, where: f.is_deleted == false)),
        deleted: count(from(f in Sanbase.Knowledge.FaqEntry, where: f.is_deleted == true))
      },
      disagreement_tweets: %{
        total: count(Sanbase.DisagreementTweets.ClassifiedTweet),
        review_required:
          count(
            from(t in Sanbase.DisagreementTweets.ClassifiedTweet,
              where: t.review_required == true
            )
          )
      },
      insights: %{total: count(Sanbase.Insight.Post)},
      comments: %{total: count(Sanbase.Comment)},
      oban: oban_by_queue(day_ago, week_ago),
      computed_at: now
    }
  end

  defp count(query), do: Repo.aggregate(query, :count)

  defp oban_by_queue(day_ago, week_ago) do
    scheduled_states = ["available", "scheduled", "retryable"]
    failed_states = ["discarded", "cancelled"]

    from(j in Oban.Job,
      where:
        j.state in ^scheduled_states or
          (j.state == "completed" and j.completed_at >= ^week_ago) or
          (j.state in ^failed_states and j.attempted_at >= ^week_ago),
      group_by: j.queue,
      select: %{
        queue: j.queue,
        scheduled: count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", j.state, ^scheduled_states)),
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
        failed_7d:
          count(
            fragment(
              "CASE WHEN ? = ANY(?) AND ? >= ? THEN 1 END",
              j.state,
              ^failed_states,
              j.attempted_at,
              ^week_ago
            )
          )
      },
      order_by: j.queue
    )
    |> Repo.all()
  end

  defp active_subscriptions_by_product do
    rows =
      from(s in Sanbase.Billing.Subscription,
        join: pl in assoc(s, :plan),
        join: pr in assoc(pl, :product),
        where: s.status in [:active, :trialing] and pl.name != "FREE",
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

    %{
      total: Enum.reduce(rows, 0, fn {_, _, c}, acc -> acc + c end),
      sanbase: Map.get(by_product, "SANBASE", %{total: 0, by_plan: []}),
      sanapi: Map.get(by_product, "SANAPI", %{total: 0, by_plan: []})
    }
  end

  defp daily_counts(schema) do
    today = Date.utc_today()
    start_date = Date.add(today, -(@series_days - 1))
    start_dt = DateTime.new!(start_date, ~T[00:00:00])

    rows =
      schema
      |> from(as: :r)
      |> where([r: r], r.inserted_at >= ^start_dt)
      |> group_by([r: r], fragment("date_trunc('day', ?)::date", r.inserted_at))
      |> select([r: r], {fragment("date_trunc('day', ?)::date", r.inserted_at), count()})
      |> Repo.all()
      |> Map.new()

    for offset <- 0..(@series_days - 1) do
      Map.get(rows, Date.add(start_date, offset), 0)
    end
  end
end
