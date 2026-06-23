defmodule SanbaseWeb.Admin.UserRankings do
  @moduledoc """
  Leaderboard of the heaviest content creators, for spotting power-users and
  potential abuse.

  The whole ranking is one round-trip: a single raw SQL with one
  `GROUP BY user_id` aggregate per creation table (charts, insights,
  dashboards, watchlists, screeners, alerts, queries, addresses, API keys),
  joined to `users`. No N+1. Team (`@santiment.net`) accounts are excluded in
  SQL, and any extra configured team emails are dropped afterwards.

  Results are cached for `@ttl_seconds` per `(rank_by, limit)`.
  """

  alias Sanbase.Repo
  alias SanbaseWeb.Admin.UserOverview.Flags

  @ttl_seconds 900
  @default_limit 200
  @max_limit 1000

  # Whitelist of sortable columns -> their (trusted) SQL identifier. Anything
  # outside this map falls back to `:total_creations`, so the user-supplied
  # `rank_by` is never interpolated into SQL.
  @rank_columns %{
    total_creations: "total_creations",
    charts: "charts",
    insights: "insights",
    dashboards: "dashboards",
    watchlists: "watchlists",
    screeners: "screeners",
    alerts: "alerts",
    queries: "queries",
    addresses: "addresses",
    api_keys: "api_keys",
    max_chart_metrics: "max_chart_metrics",
    total_chart_metrics: "total_chart_metrics",
    max_watchlist_assets: "max_watchlist_assets"
  }

  @doc "The list of valid `rank_by` atoms (for building the UI dropdown)."
  @spec rank_options() :: [atom()]
  def rank_options, do: Map.keys(@rank_columns)

  @doc """
  Returns `{:ok, %{rows: [...], rank_by: atom, limit: int, computed_at: DateTime}}`.

  Options:
    * `:rank_by` - one of `rank_options/0` (atom or string). Defaults to `:total_creations`.
    * `:limit`   - number of rows (1..#{@max_limit}). Defaults to #{@default_limit}.
  """
  @spec get(keyword()) :: {:ok, map()} | {:error, term()}
  def get(opts \\ []) do
    rank_by = normalize_rank_by(Keyword.get(opts, :rank_by))
    limit = normalize_limit(Keyword.get(opts, :limit))

    cache_key = {__MODULE__, :get, rank_by, limit, :v1} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, @ttl_seconds}, fn -> {:ok, compute(rank_by, limit)} end)
  end

  defp normalize_rank_by(rank_by) when is_atom(rank_by) and not is_nil(rank_by) do
    if Map.has_key?(@rank_columns, rank_by), do: rank_by, else: :total_creations
  end

  defp normalize_rank_by(rank_by) when is_binary(rank_by) do
    Enum.find(rank_options(), :total_creations, &(Atom.to_string(&1) == rank_by))
  end

  defp normalize_rank_by(_), do: :total_creations

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {n, _} -> normalize_limit(n)
      :error -> @default_limit
    end
  end

  defp normalize_limit(_), do: @default_limit

  defp compute(rank_by, limit) do
    order_column = Map.fetch!(@rank_columns, rank_by)

    {:ok, %{rows: rows}} = Repo.query(sql(order_column), [limit])

    ranked =
      rows
      |> Enum.map(&row_to_map/1)
      |> drop_extra_team_members()
      |> Enum.map(&attach_flags/1)

    %{rows: ranked, rank_by: rank_by, limit: limit, computed_at: DateTime.utc_now()}
  end

  defp row_to_map([
         user_id,
         email,
         username,
         charts,
         insights,
         dashboards,
         watchlists,
         screeners,
         alerts,
         queries,
         addresses,
         api_keys,
         max_chart_metrics,
         total_chart_metrics,
         max_watchlist_assets,
         total_creations,
         is_paid
       ]) do
    %{
      user_id: user_id,
      email: email,
      username: username,
      charts: charts,
      insights: insights,
      dashboards: dashboards,
      watchlists: watchlists,
      screeners: screeners,
      alerts: alerts,
      queries: queries,
      addresses: addresses,
      api_keys: api_keys,
      max_chart_metrics: max_chart_metrics,
      total_chart_metrics: total_chart_metrics,
      max_watchlist_assets: max_watchlist_assets,
      total_creations: total_creations,
      is_paid: is_paid
    }
  end

  defp drop_extra_team_members(rows) do
    team_emails = MapSet.new(Sanbase.MCP.ToolInvocation.team_emails())

    Enum.reject(rows, fn row ->
      is_binary(row.email) and MapSet.member?(team_emails, String.downcase(row.email))
    end)
  end

  defp attach_flags(row) do
    Map.put(row, :flags, Flags.compute(row))
  end

  # `order_column` is always a value from @rank_columns (trusted); `limit` is
  # bound as $1. Nothing user-supplied is interpolated.
  defp sql(order_column) do
    """
    WITH c_charts AS (
      SELECT user_id,
             COUNT(*) AS cnt,
             COALESCE(MAX(COALESCE(array_length(metrics, 1), 0)), 0) AS max_metrics,
             COALESCE(SUM(COALESCE(array_length(metrics, 1), 0)), 0) AS total_metrics
      FROM chart_configurations
      WHERE is_deleted = false
      GROUP BY user_id
    ),
    c_insights AS (
      SELECT user_id, COUNT(*) AS cnt FROM posts WHERE is_deleted = false GROUP BY user_id
    ),
    c_dashboards AS (
      SELECT user_id, COUNT(*) AS cnt FROM dashboards WHERE is_deleted = false GROUP BY user_id
    ),
    c_watchlists AS (
      SELECT user_id, COUNT(*) AS cnt FROM user_lists
      WHERE is_deleted = false AND is_screener = false GROUP BY user_id
    ),
    c_screeners AS (
      SELECT user_id, COUNT(*) AS cnt FROM user_lists
      WHERE is_deleted = false AND is_screener = true GROUP BY user_id
    ),
    c_wl_assets AS (
      SELECT user_id, COALESCE(MAX(asset_count), 0) AS max_assets
      FROM (
        SELECT ul.user_id AS user_id, ul.id AS list_id, COUNT(li.id) AS asset_count
        FROM user_lists ul
        LEFT JOIN list_items li ON li.user_list_id = ul.id
        WHERE ul.is_deleted = false
        GROUP BY ul.user_id, ul.id
      ) per_list
      GROUP BY user_id
    ),
    c_alerts AS (
      SELECT user_id, COUNT(*) AS cnt FROM user_triggers WHERE is_deleted = false GROUP BY user_id
    ),
    c_queries AS (
      SELECT user_id, COUNT(*) AS cnt FROM queries WHERE is_deleted = false GROUP BY user_id
    ),
    c_addresses AS (
      SELECT user_id, COUNT(*) AS cnt FROM blockchain_address_user_pairs GROUP BY user_id
    ),
    c_apikeys AS (
      SELECT user_id, COUNT(*) AS cnt FROM user_api_key_tokens GROUP BY user_id
    ),
    c_paid AS (
      SELECT DISTINCT user_id FROM subscriptions
      WHERE status IN ('active', 'past_due')
    ),
    creators AS (
      SELECT user_id FROM c_charts
      UNION SELECT user_id FROM c_insights
      UNION SELECT user_id FROM c_dashboards
      UNION SELECT user_id FROM c_watchlists
      UNION SELECT user_id FROM c_screeners
      UNION SELECT user_id FROM c_alerts
      UNION SELECT user_id FROM c_queries
      UNION SELECT user_id FROM c_addresses
      UNION SELECT user_id FROM c_apikeys
    )
    SELECT * FROM (
      SELECT
        u.id AS user_id,
        u.email AS email,
        u.username AS username,
        COALESCE(c.cnt, 0) AS charts,
        COALESCE(i.cnt, 0) AS insights,
        COALESCE(d.cnt, 0) AS dashboards,
        COALESCE(w.cnt, 0) AS watchlists,
        COALESCE(s.cnt, 0) AS screeners,
        COALESCE(a.cnt, 0) AS alerts,
        COALESCE(q.cnt, 0) AS queries,
        COALESCE(ad.cnt, 0) AS addresses,
        COALESCE(ak.cnt, 0) AS api_keys,
        COALESCE(c.max_metrics, 0) AS max_chart_metrics,
        COALESCE(c.total_metrics, 0) AS total_chart_metrics,
        COALESCE(wa.max_assets, 0) AS max_watchlist_assets,
        (COALESCE(c.cnt, 0) + COALESCE(i.cnt, 0) + COALESCE(d.cnt, 0) + COALESCE(w.cnt, 0)
          + COALESCE(s.cnt, 0) + COALESCE(a.cnt, 0) + COALESCE(q.cnt, 0)) AS total_creations,
        (p.user_id IS NOT NULL) AS is_paid
      FROM creators cr
      JOIN users u ON u.id = cr.user_id
      LEFT JOIN c_charts c ON c.user_id = u.id
      LEFT JOIN c_insights i ON i.user_id = u.id
      LEFT JOIN c_dashboards d ON d.user_id = u.id
      LEFT JOIN c_watchlists w ON w.user_id = u.id
      LEFT JOIN c_screeners s ON s.user_id = u.id
      LEFT JOIN c_alerts a ON a.user_id = u.id
      LEFT JOIN c_queries q ON q.user_id = u.id
      LEFT JOIN c_addresses ad ON ad.user_id = u.id
      LEFT JOIN c_apikeys ak ON ak.user_id = u.id
      LEFT JOIN c_wl_assets wa ON wa.user_id = u.id
      LEFT JOIN c_paid p ON p.user_id = u.id
      WHERE u.email IS NULL OR u.email NOT ILIKE '%@santiment.net'
    ) ranked
    ORDER BY #{order_column} DESC NULLS LAST, total_creations DESC
    LIMIT $1
    """
  end
end
