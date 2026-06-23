defmodule SanbaseWeb.Admin.UserOverview do
  @moduledoc """
  A single user's full footprint for the admin overview page: subscription
  status (current + past, paid?), everything they've created with a "depth"
  measure for each (chart metric count, watchlist asset count, dashboard
  widget count), plus the abuse `Flags`.

  Every list is fetched with one scoped query per creation type — no N+1.
  The whole thing is cached for `@ttl_seconds` per user.
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription
  alias Sanbase.Chart
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.UserList.ListItem
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Queries.Query
  alias SanbaseWeb.Admin.UserOverview.Flags

  @ttl_seconds 300
  # Cap per-type lists so a prolific user can't produce a huge payload. The
  # `count` is always exact (computed separately); only the displayed list is
  # capped, and it's ordered so the deepest items come first.
  @list_limit 100

  @paid_statuses [:active, :past_due]

  @doc """
  Resolve a free-text search term to a user id.

  Numeric -> id, contains `@` -> email, otherwise -> username.
  Returns `{:ok, user_id}` or `{:error, reason}`.
  """
  @spec lookup(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def lookup(term) when is_binary(term) do
    term = String.trim(term)

    result =
      cond do
        term == "" -> {:error, "Enter a user id, email or username"}
        Regex.match?(~r/^\d+$/, term) -> User.by_id(String.to_integer(term))
        String.contains?(term, "@") -> User.by_email(term)
        true -> User.by_username(term)
      end

    case result do
      {:ok, %User{id: id}} -> {:ok, id}
      {:error, _} -> {:error, "No user found for #{inspect(term)}"}
    end
  end

  @doc "Cached per-user overview. Returns `{:ok, map}` or `{:error, term}`."
  @spec get(non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def get(user_id) when is_integer(user_id) do
    cache_key = {__MODULE__, :get, user_id, :v1} |> Sanbase.Cache.hash()
    Sanbase.Cache.get_or_store({cache_key, @ttl_seconds}, fn -> compute(user_id) end)
  end

  defp compute(user_id) do
    case User.by_id(user_id) do
      {:ok, %User{} = user} -> {:ok, build(user)}
      {:error, _} -> {:error, "No user with id #{user_id}"}
    end
  end

  defp build(%User{} = user) do
    subscription = subscription_info(user)
    creations = creations(user.id)

    max_chart_metrics =
      creations.charts.list |> Enum.map(& &1.metrics) |> max0()

    max_watchlist_assets =
      (creations.watchlists.list ++ creations.screeners.list)
      |> Enum.map(& &1.assets)
      |> max0()

    total_creations =
      creations.insights.count + creations.charts.count + creations.dashboards.count +
        creations.watchlists.count + creations.screeners.count + creations.alerts.count +
        creations.queries.count

    totals = %{
      total_creations: total_creations,
      max_chart_metrics: max_chart_metrics,
      max_watchlist_assets: max_watchlist_assets
    }

    flags =
      Flags.compute(%{
        charts: creations.charts.count,
        max_chart_metrics: max_chart_metrics,
        max_watchlist_assets: max_watchlist_assets,
        total_creations: total_creations,
        api_keys: creations.api_keys.count,
        is_paid: subscription.is_paid
      })

    %{
      user: %{
        id: user.id,
        email: user.email,
        username: user.username,
        inserted_at: user.inserted_at,
        is_team: Sanbase.MCP.ToolInvocation.team_member?(user)
      },
      subscription: subscription,
      creations: creations,
      totals: totals,
      flags: flags,
      computed_at: DateTime.utc_now()
    }
  end

  # ── Subscriptions ────────────────────────────────────────────────────────

  defp subscription_info(%User{id: user_id}) do
    all =
      from(s in Subscription,
        where: s.user_id == ^user_id,
        order_by: [desc: s.inserted_at],
        preload: [plan: :product]
      )
      |> Repo.all()
      |> Enum.map(&subscription_row/1)

    current = Enum.filter(all, &(&1.status in [:active, :past_due, :trialing]))
    is_paid = Enum.any?(all, &(&1.status in @paid_statuses))

    %{is_paid: is_paid, current: current, all: all}
  end

  defp subscription_row(%Subscription{} = s) do
    %{
      id: s.id,
      product: s.plan && s.plan.product && s.plan.product.name,
      plan: s.plan && s.plan.name,
      status: s.status,
      type: s.type,
      current_period_end: s.current_period_end,
      trial_end: s.trial_end,
      cancel_at_period_end: s.cancel_at_period_end,
      inserted_at: s.inserted_at
    }
  end

  # ── Creations ────────────────────────────────────────────────────────────

  defp creations(user_id) do
    %{
      insights: insights(user_id),
      charts: charts(user_id),
      dashboards: dashboards(user_id),
      watchlists: watchlists(user_id, false),
      screeners: watchlists(user_id, true),
      alerts: alerts(user_id),
      queries: queries(user_id),
      addresses: %{count: count_addresses(user_id)},
      api_keys: %{count: count_api_keys(user_id)}
    }
  end

  defp charts(user_id) do
    base = from(c in Chart.Configuration, where: c.user_id == ^user_id and c.is_deleted == false)

    list =
      from(c in base,
        order_by: [desc: fragment("COALESCE(array_length(?, 1), 0)", c.metrics)],
        limit: @list_limit,
        select: %{
          id: c.id,
          title: c.title,
          is_public: c.is_public,
          metrics: fragment("COALESCE(array_length(?, 1), 0)", c.metrics),
          complexity_bytes:
            fragment(
              "COALESCE(pg_column_size(?), 0) + COALESCE(pg_column_size(?), 0) + COALESCE(pg_column_size(?), 0)",
              c.metrics_json,
              c.queries,
              c.options
            ),
          inserted_at: c.inserted_at
        }
      )
      |> Repo.all()

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp dashboards(user_id) do
    base = from(d in Dashboard, where: d.user_id == ^user_id and d.is_deleted == false)

    list =
      from(d in base,
        left_join: m in "dashboard_query_mappings",
        on: m.dashboard_id == d.id,
        group_by: d.id,
        order_by: [
          desc:
            fragment(
              "COALESCE(jsonb_array_length(?), 0) + COALESCE(jsonb_array_length(?), 0)",
              d.text_widgets,
              d.image_widgets
            )
        ],
        limit: @list_limit,
        select: %{
          id: d.id,
          name: d.name,
          is_public: d.is_public,
          widgets:
            fragment(
              "COALESCE(jsonb_array_length(?), 0) + COALESCE(jsonb_array_length(?), 0)",
              d.text_widgets,
              d.image_widgets
            ),
          queries: count(m.dashboard_id),
          inserted_at: d.inserted_at
        }
      )
      |> Repo.all()

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp watchlists(user_id, is_screener?) do
    base =
      from(ul in UserList,
        where:
          ul.user_id == ^user_id and ul.is_deleted == false and
            ul.is_screener == ^is_screener?
      )

    list =
      from(ul in base,
        left_join: li in ListItem,
        on: li.user_list_id == ul.id,
        group_by: ul.id,
        order_by: [desc: count(li.id)],
        limit: @list_limit,
        select: %{
          id: ul.id,
          name: ul.name,
          is_public: ul.is_public,
          assets: count(li.id),
          inserted_at: ul.inserted_at
        }
      )
      |> Repo.all()

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp insights(user_id) do
    base = from(p in Post, where: p.user_id == ^user_id and p.is_deleted == false)

    list =
      from(p in base,
        order_by: [desc: p.inserted_at],
        limit: @list_limit,
        select: %{
          id: p.id,
          title: p.title,
          ready_state: p.ready_state,
          state: p.state,
          inserted_at: p.inserted_at
        }
      )
      |> Repo.all()

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp alerts(user_id) do
    base = from(ut in UserTrigger, where: ut.user_id == ^user_id and ut.is_deleted == false)

    list =
      from(ut in base,
        order_by: [desc: ut.inserted_at],
        limit: @list_limit,
        select: %{id: ut.id, trigger: ut.trigger, inserted_at: ut.inserted_at}
      )
      |> Repo.all()
      |> Enum.map(fn row ->
        %{
          id: row.id,
          title: row.trigger && row.trigger.title,
          is_public: !!(row.trigger && row.trigger.is_public),
          is_active: !!(row.trigger && row.trigger.is_active),
          inserted_at: row.inserted_at
        }
      end)

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp queries(user_id) do
    base = from(q in Query, where: q.user_id == ^user_id and q.is_deleted == false)

    list =
      from(q in base,
        order_by: [desc: q.inserted_at],
        limit: @list_limit,
        select: %{id: q.id, name: q.name, is_public: q.is_public, inserted_at: q.inserted_at}
      )
      |> Repo.all()

    %{count: Repo.aggregate(base, :count, :id), list: list}
  end

  defp count_addresses(user_id) do
    from(p in "blockchain_address_user_pairs", where: p.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp count_api_keys(user_id) do
    from(t in "user_api_key_tokens", where: t.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp max0([]), do: 0
  defp max0(list), do: Enum.max(list)
end
