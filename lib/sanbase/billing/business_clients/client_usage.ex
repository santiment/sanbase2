defmodule Sanbase.Billing.BusinessClients.ClientUsage do
  @moduledoc ~s"""
  What one client does with the product, for the person about to contact them: what
  they call through the API and how that changed, which parts of Sanbase they visit,
  and what they have built there (watchlists, alerts, saved charts, dashboards and SQL
  queries).

  Usage compares the last 30 whole days (up to yesterday) with the 30 days
  before. Every part is read separately and is `:error` when its query failed, so one
  slow source never hides the others.
  """

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Repo

  require Logger

  @window_days 30
  @max_queries 200
  @max_assets 100
  @max_user_agents 20
  @sql_run_queries ~w(runRawSqlQuery computeRawClickhouseQuery runDashboardSqlQuery)

  @type change :: %{current: non_neg_integer(), previous: non_neg_integer()}
  @type api :: %{
          calls: change(),
          errors: non_neg_integer(),
          queries: [
            %{name: String.t(), current: integer(), previous: integer(), errors: integer()}
          ],
          assets: [%{slug: String.t(), current: integer(), previous: integer()}],
          connections: [%{label: String.t(), calls: integer(), share: float()}]
        }
  @type web :: %{
          areas: [%{area: String.t(), current: integer(), previous: integer()}],
          sql_runs: change()
        }
  @type creation :: %{
          kind: atom(),
          label: String.t(),
          total: non_neg_integer(),
          active: non_neg_integer() | nil,
          changed_recently: non_neg_integer(),
          last_changed_at: NaiveDateTime.t() | nil,
          last_fired_at: DateTime.t() | nil
        }

  @doc "The number of days in each of the two usage windows."
  def window_days, do: @window_days

  @doc ~s"""
  The windows on `today`: `%{from, middle, until}` as midnights UTC. The current window
  is `[middle, until)`, the previous `[from, middle)`; `until` is today's midnight, so
  today, not over yet, is left out.
  """
  @spec windows(Date.t()) :: %{from: DateTime.t(), middle: DateTime.t(), until: DateTime.t()}
  def windows(today) do
    until = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    middle = DateTime.add(until, -@window_days, :day)
    %{from: DateTime.add(middle, -@window_days, :day), middle: middle, until: until}
  end

  # ─── API ─────────────────────────────────────────────────────────────────

  @doc ~s"""
  The client's API key calls in the two windows: in total, per GraphQL query or metric,
  per asset, and per kind of program making them (from the user agent). `errors` are
  calls in the current window that failed or returned GraphQL errors.
  """
  @spec api(integer(), Date.t()) :: {:ok, api()} | :error
  def api(user_id, today) do
    params = Map.put(windows(today), :user_id, user_id)

    with {:ok, queries} <- api_queries(params),
         {:ok, assets} <- api_assets(params),
         {:ok, connections} <- api_connections(params) do
      {:ok,
       %{
         calls: %{
           current: Enum.sum_by(queries, & &1.current),
           previous: Enum.sum_by(queries, & &1.previous)
         },
         errors: Enum.sum_by(queries, & &1.errors),
         queries: queries,
         assets: assets,
         connections: connections
       }}
    end
  end

  defp api_queries(params) do
    sql = """
    SELECT
      query,
      toUInt64(countIf(dt >= toDateTime({{middle}}))) AS current,
      toUInt64(countIf(dt < toDateTime({{middle}}))) AS previous,
      toUInt64(countIf(dt >= toDateTime({{middle}})
        AND (status_code >= 400 OR ifNull(has_graphql_errors, 0) = 1))) AS errors
    FROM api_call_data
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{until}})
      AND auth_method = 'apikey' AND user_id = {{user_id}}
    GROUP BY query
    ORDER BY current + previous DESC
    LIMIT #{@max_queries}
    """

    run(sql, params, "api_queries", fn [query, current, previous, errors] ->
      %{name: query, current: current, previous: previous, errors: errors}
    end)
  end

  defp api_assets(params) do
    sql = """
    SELECT
      slug,
      toUInt64(countIf(dt >= toDateTime({{middle}}))) AS current,
      toUInt64(countIf(dt < toDateTime({{middle}}))) AS previous
    FROM api_call_data
    ARRAY JOIN extractAll(ifNull(selector, ''), '"slug":"([^"]+)"') AS slug
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{until}})
      AND auth_method = 'apikey' AND user_id = {{user_id}}
    GROUP BY slug
    ORDER BY current + previous DESC
    LIMIT #{@max_assets}
    """

    run(sql, params, "api_assets", fn [slug, current, previous] ->
      %{slug: slug, current: current, previous: previous}
    end)
  end

  defp api_connections(params) do
    sql = """
    SELECT ifNull(user_agent, ''), toUInt64(count())
    FROM api_call_data
    WHERE dt >= toDateTime({{middle}}) AND dt < toDateTime({{until}})
      AND auth_method = 'apikey' AND user_id = {{user_id}}
    GROUP BY user_agent
    ORDER BY count() DESC
    LIMIT #{@max_user_agents}
    """

    with {:ok, rows} <- run(sql, params, "api_connections", fn [ua, calls] -> {ua, calls} end) do
      {:ok, group_connections(rows)}
    end
  end

  defp group_connections(rows) do
    total = Enum.sum_by(rows, &elem(&1, 1))

    rows
    |> Enum.group_by(fn {ua, _calls} -> connection_label(ua) end, &elem(&1, 1))
    |> Enum.map(fn {label, calls} ->
      sum = Enum.sum(calls)
      %{label: label, calls: sum, share: sum / max(total, 1)}
    end)
    |> Enum.sort_by(& &1.calls, :desc)
  end

  @doc ~s"""
  What kind of program a user agent belongs to: Python, Google Sheets, JavaScript and
  so on. An agent not recognised is shown as it is, cut to 40 characters.
  """
  @spec connection_label(String.t() | nil) :: String.t()
  def connection_label(ua) when ua in [nil, ""], do: "Unknown"

  @connection_rules [
    {:contains, "google-apps-script", "Google Sheets"},
    {:contains, ["microsoft office", "powerquery", "excel"], "Excel"},
    {:contains, ["python", "aiohttp", "httpx", "urllib"], "Python"},
    {:contains, ["node", "deno", "axios", "undici", "bun/"], "JavaScript"},
    {:contains, "go-http-client", "Go"},
    {:starts_with, "curl", "curl"},
    {:starts_with, "postman", "Postman"},
    {:starts_with, "mozilla", "Browser"}
  ]

  def connection_label(ua) do
    lower = String.downcase(ua)

    Enum.find_value(@connection_rules, String.slice(ua, 0, 40), fn
      {:contains, pattern, label} -> if String.contains?(lower, pattern), do: label
      {:starts_with, prefix, label} -> if String.starts_with?(lower, prefix), do: label
    end)
  end

  @doc ~s"""
  A GraphQL query name as people know it: `getMetric|exchange_inflow` is the metric
  `exchange_inflow`; any other query keeps its name.
  """
  @spec query_label(String.t()) :: String.t()
  def query_label("getMetric|" <> metric), do: metric
  def query_label(query), do: query

  # ─── Sanbase ─────────────────────────────────────────────────────────────

  @doc ~s"""
  The client's use of the Sanbase web app in the two windows: page views per area of
  the app, and SQL queries run in Santiment Queries.
  """
  @spec web(integer(), Date.t()) :: {:ok, web()} | :error
  def web(user_id, today) do
    params = Map.put(windows(today), :user_id, user_id)

    with {:ok, areas} <- web_areas(params),
         {:ok, sql_runs} <- sql_runs(params) do
      {:ok, %{areas: areas, sql_runs: sql_runs}}
    end
  end

  defp web_areas(params) do
    sql = """
    SELECT
      splitByChar('/', multiIf(
        JSONExtractString(metadata, 'url_pathname') != '', JSONExtractString(metadata, 'url_pathname'),
        JSONExtractString(metadata, 'source_url_pathname') != '', JSONExtractString(metadata, 'source_url_pathname'),
        path(JSONExtractString(metadata, 'url'))))[2] AS section,
      toUInt64(countIf(dt >= toDateTime({{middle}}))) AS current,
      toUInt64(countIf(dt < toDateTime({{middle}}))) AS previous
    FROM sanbase_user_events
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{until}})
      AND event_name = 'page_view' AND user_id = {{user_id}}
    GROUP BY section
    """

    with {:ok, rows} <-
           run(sql, params, "web_areas", fn [section, current, previous] ->
             {area_label(section), current, previous}
           end) do
      {:ok, sum_areas(rows)}
    end
  end

  defp sum_areas(rows) do
    rows
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {area, group} ->
      %{
        area: area,
        current: Enum.sum_by(group, &elem(&1, 1)),
        previous: Enum.sum_by(group, &elem(&1, 2))
      }
    end)
    |> Enum.sort_by(&{-&1.current, -&1.previous})
  end

  @doc ~s"""
  The area of the Sanbase app a page belongs to, from the first part of its path.
  """
  @spec area_label(String.t() | nil) :: String.t()
  def area_label(section) when section in ["charts", "__charts", "chart"], do: "Charts"
  def area_label(section) when section in ["watchlist", "watchlists"], do: "Watchlists"
  def area_label("screener"), do: "Screeners"
  def area_label("alerts"), do: "Alerts"
  def area_label("insights"), do: "Insights"
  def area_label("social-trends"), do: "Social trends"

  def area_label(section) when section in ["dashboard", "dashboards", "query", "queries"],
    do: "Dashboards and SQL"

  def area_label("labs"), do: "Labs"
  def area_label("dev-activity"), do: "Dev activity"
  def area_label("pricing"), do: "Pricing page"
  def area_label(section) when section in ["account", "profile"], do: "Account"
  def area_label("community"), do: "Community"
  def area_label(section) when section in [nil, ""], do: "Home"
  def area_label(_section), do: "Other"

  defp sql_runs(params) do
    sql = """
    SELECT
      toUInt64(countIf(dt >= toDateTime({{middle}}))),
      toUInt64(countIf(dt < toDateTime({{middle}})))
    FROM api_call_data
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{until}})
      AND user_id = {{user_id}} AND query IN ({{sql_queries}})
    """

    params = Map.put(params, :sql_queries, @sql_run_queries)

    case run(sql, params, "sql_runs", fn [current, previous] -> {current, previous} end) do
      {:ok, [{current, previous}]} -> {:ok, %{current: current, previous: previous}}
      {:ok, []} -> {:ok, %{current: 0, previous: 0}}
      :error -> :error
    end
  end

  # ─── What they built ─────────────────────────────────────────────────────

  @doc ~s"""
  What the client has built in Sanbase, deleted items left out: watchlists, screeners,
  alerts, saved chart layouts, dashboards, SQL queries and insights. For each the
  number, how many changed in the last #{@window_days} days and when the last one
  changed; for alerts also how many are on and when one last fired.
  """
  @spec creations(integer(), Date.t()) :: {:ok, [creation()]} | :error
  def creations(user_id, today) do
    since = NaiveDateTime.new!(Date.add(today, -@window_days), ~T[00:00:00])

    sql = """
    SELECT 'watchlists', count(*), NULL::bigint, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM user_lists WHERE user_id = $1 AND NOT is_deleted AND NOT is_screener
    UNION ALL
    SELECT 'screeners', count(*), NULL, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM user_lists WHERE user_id = $1 AND NOT is_deleted AND is_screener
    UNION ALL
    SELECT 'alerts', count(*),
      count(*) FILTER (WHERE coalesce((trigger->>'is_active')::boolean, false)
        AND NOT coalesce((trigger->>'is_frozen')::boolean, false)),
      count(*) FILTER (WHERE updated_at >= $2), max(updated_at),
      (SELECT max(fired.value) FROM user_triggers t2,
         jsonb_each_text(CASE WHEN jsonb_typeof(t2.trigger->'last_triggered') = 'object'
           THEN t2.trigger->'last_triggered' ELSE '{}'::jsonb END) AS fired
       WHERE t2.user_id = $1 AND NOT t2.is_deleted)
    FROM user_triggers WHERE user_id = $1 AND NOT is_deleted
    UNION ALL
    SELECT 'chart_layouts', count(*), NULL, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM chart_configurations WHERE user_id = $1 AND NOT is_deleted
    UNION ALL
    SELECT 'dashboards', count(*), NULL, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM dashboards WHERE user_id = $1 AND NOT is_deleted
    UNION ALL
    SELECT 'sql_queries', count(*), NULL, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM queries WHERE user_id = $1 AND NOT is_deleted
    UNION ALL
    SELECT 'insights', count(*), NULL, count(*) FILTER (WHERE updated_at >= $2), max(updated_at), NULL
    FROM posts WHERE user_id = $1 AND NOT is_deleted AND ready_state = 'published'
    """

    case Repo.query(sql, [user_id, since]) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, &to_creation/1)}

      {:error, error} ->
        Logger.warning("[BusinessClients.ClientUsage] creations failed: #{inspect(error)}")
        :error
    end
  end

  @creation_labels %{
    "watchlists" => {:watchlists, "Watchlists"},
    "screeners" => {:screeners, "Screeners"},
    "alerts" => {:alerts, "Alerts"},
    "chart_layouts" => {:chart_layouts, "Saved chart layouts"},
    "dashboards" => {:dashboards, "Dashboards"},
    "sql_queries" => {:sql_queries, "SQL queries"},
    "insights" => {:insights, "Published insights"}
  }

  defp to_creation([kind, total, active, changed, last_changed, last_fired]) do
    {kind, label} = Map.fetch!(@creation_labels, kind)

    %{
      kind: kind,
      label: label,
      total: total,
      active: active,
      changed_recently: changed,
      last_changed_at: last_changed,
      last_fired_at: parse_datetime(last_fired)
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  # ─── Summary ─────────────────────────────────────────────────────────────

  @creation_order [
    :alerts,
    :watchlists,
    :screeners,
    :chart_layouts,
    :dashboards,
    :sql_queries,
    :insights
  ]

  @doc ~s"""
  `creations/2` in a fixed order: alerts first, then watchlists and the rest.
  """
  @spec sort_creations([creation()]) :: [creation()]
  def sort_creations(creations) do
    Enum.sort_by(creations, fn c -> Enum.find_index(@creation_order, &(&1 == c.kind)) end)
  end

  @doc ~s"""
  A few plain sentences to open a conversation with the client, most important first,
  built by fixed rules from the client row (`active_days`, `active_days_prev`,
  `plan_limit`) and the results of `api/2`, `web/2` and `creations/2`. A part that
  failed (`:error`) adds nothing.
  """
  @spec summary(map(), {:ok, api()} | :error, {:ok, web()} | :error, {:ok, [creation()]} | :error) ::
          [String.t()]
  def summary(client, api, web, creations) do
    [
      activity_sentence(client),
      api_change_sentence(api),
      stopped_sentences(api),
      errors_sentence(api),
      started_sentence(api),
      upsell_sentence(client),
      pricing_sentence(web),
      creations_sentence(client, creations)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp activity_sentence(%{active_days: days, active_days_prev: prev})
       when is_integer(days) and is_integer(prev) and days != prev,
       do: "Active on #{days} of the last #{@window_days} days, was #{prev}."

  defp activity_sentence(%{active_days: days}) when is_integer(days),
    do: "Active on #{days} of the last #{@window_days} days."

  defp activity_sentence(_client), do: nil

  @min_calls_to_compare 100

  defp api_change_sentence({:ok, %{calls: %{current: 0, previous: 0}}}), do: nil

  defp api_change_sentence({:ok, %{calls: %{current: current, previous: 0}}}),
    do: "Started using the API: #{group(current)} calls in the last #{@window_days} days."

  defp api_change_sentence({:ok, %{calls: %{current: current, previous: previous}}})
       when previous >= @min_calls_to_compare do
    change = (current - previous) * 100 / previous
    compared = "#{group(current)} against #{group(previous)} in the #{@window_days} days before"

    cond do
      change <= -30 -> "API calls down #{round(-change)}%: #{compared}."
      change >= 30 -> "API calls up #{round(change)}%: #{compared}."
      true -> nil
    end
  end

  defp api_change_sentence(_api), do: nil

  # A query that was at least 10% of the calls before and fell by 90% or more.
  defp stopped_sentences({:ok, %{queries: queries, calls: %{previous: total}}})
       when total >= @min_calls_to_compare do
    queries
    |> Enum.filter(&(&1.previous >= total * 0.1 and &1.current <= &1.previous * 0.1))
    |> Enum.sort_by(& &1.previous, :desc)
    |> Enum.take(2)
    |> Enum.map(fn q ->
      verb = if q.current == 0, do: "Stopped calling", else: "Almost stopped calling"
      "#{verb} #{query_label(q.name)}, which was #{share(q.previous, total)} of their calls."
    end)
  end

  defp stopped_sentences(_api), do: []

  defp started_sentence({:ok, %{queries: queries, calls: %{current: total, previous: previous}}})
       when total >= @min_calls_to_compare and previous > 0 do
    case Enum.find(queries, &(&1.previous == 0 and &1.current >= total * 0.1)) do
      nil ->
        nil

      q ->
        "Started calling #{query_label(q.name)}, now #{share(q.current, total)} of their calls."
    end
  end

  defp started_sentence(_api), do: nil

  # Worth raising from 5% failed calls, and at least 50 of them.
  defp errors_sentence({:ok, %{errors: errors, calls: %{current: total}, queries: queries}})
       when errors >= 50 and errors >= total * 0.05 do
    worst = Enum.max_by(queries, & &1.errors)

    "#{share(errors, total)} of API calls failed in the last #{@window_days} days, " <>
      "most of them #{query_label(worst.name)}."
  end

  defp errors_sentence(_api), do: nil

  defp upsell_sentence(%{plan_limit: %{upsell?: true, upsell_reason: reason}}),
    do: "Upsell: #{reason}."

  defp upsell_sentence(_client), do: nil

  defp pricing_sentence({:ok, %{areas: areas}}) do
    case Enum.find(areas, &(&1.area == "Pricing page" and &1.current > 0)) do
      nil -> nil
      area -> "Visited the pricing page #{area.current} time(s) in the last #{@window_days} days."
    end
  end

  defp pricing_sentence(_web), do: nil

  defp creations_sentence(client, {:ok, creations}) do
    built =
      creations
      |> sort_creations()
      |> Enum.flat_map(fn
        %{kind: :alerts, active: active} when is_integer(active) and active > 0 ->
          ["#{active} active alert(s)"]

        %{kind: kind, total: total} when kind != :alerts and total > 0 ->
          ["#{total} #{creation_noun(kind)}"]

        _ ->
          []
      end)

    cond do
      built != [] ->
        "Has built #{Enum.join(built, ", ")}."

      client[:business_reason] != :plan ->
        "Has built nothing in Sanbase: no alerts, watchlists or saved charts."

      true ->
        nil
    end
  end

  defp creations_sentence(_client, _creations), do: nil

  defp creation_noun(:watchlists), do: "watchlist(s)"
  defp creation_noun(:screeners), do: "screener(s)"
  defp creation_noun(:chart_layouts), do: "saved chart layout(s)"
  defp creation_noun(:dashboards), do: "dashboard(s)"
  defp creation_noun(:sql_queries), do: "SQL quer(ies)"
  defp creation_noun(:insights), do: "published insight(s)"

  defp share(part, total) when total > 0, do: "#{round(part * 100 / total)}%"
  defp share(_part, _total), do: "0%"

  defp group(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp run(sql, params, name, row_fun) do
    sql
    |> Sanbase.Clickhouse.Query.new(params)
    |> ClickhouseRepo.query_transform(row_fun)
    |> case do
      {:ok, rows} ->
        {:ok, rows}

      {:error, error} ->
        Logger.warning("[BusinessClients.ClientUsage] #{name} failed: #{inspect(error)}")
        :error
    end
  end
end
