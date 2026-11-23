defmodule Sanbase.MCP.Dev.ExecuteSqlTool do
  @moduledoc """
  Run a read-only ClickHouse SQL query with the table access of a SanAPI BUSINESS_MAX
  subscription, through Santiment Queries (the same engine as the Queries page and the
  `runRawSqlQuery` API).

  Writing queries:
  - Find tables with `list_tables` and their columns and sorting keys with
    `describe_tables`. Filter on the sorting key columns (usually an asset or metric id
    and a datetime) to keep queries fast.
  - Pass values as `{{name}}` placeholders with `parameters` instead of pasting them into
    the SQL, e.g. `WHERE asset_id = get_asset_id({{slug}})` with `{"slug": "bitcoin"}`.
  - Always add a LIMIT and prefer aggregates. At most `max_rows` rows are returned;
    `truncated: true` means the query returned more.

  Use it as a screener: rank and filter many assets in one query instead of fetching
  metrics asset by asset. For example: the 10 projects among the top 100 by market cap
  whose social volume grew the most week over week, assets whose exchange inflow spiked
  versus their 30-day average, or the largest daily active address growth among DeFi
  tokens.

  Most metrics live in `daily_metrics_v2` (daily) and `intraday_metrics` (5-minute to
  hourly), keyed by `asset_id`, `metric_id` and `dt`. Resolve ids with
  `get_asset_id('bitcoin')` and `get_metric_id('daily_closing_marketcap_usd')`, and get
  slugs from `asset_metadata FINAL` (`name` is the slug). A value can be stored more
  than once per `(asset_id, metric_id, dt)`: keep the latest with
  `argMax(value, computed_at) ... GROUP BY asset_id, dt` before summing. Social volume
  is the `social_volume` metric in `intraday_metrics`. Use explicit `JOIN ... ON`:
  ClickHouse rejects more than one `USING` join in a query. A screener for the example
  above:

      WITH
        top_mcap AS (
          SELECT asset_id, argMax(value, dt) AS marketcap_usd
          FROM daily_metrics_v2
          WHERE metric_id = get_metric_id('daily_closing_marketcap_usd') AND dt >= today() - 3
          GROUP BY asset_id
          ORDER BY marketcap_usd DESC
          LIMIT 100
        ),
        social AS (
          SELECT
            asset_id,
            sumIf(value, dt >= now() - INTERVAL 7 DAY) AS sv_last_7d,
            sumIf(value, dt < now() - INTERVAL 7 DAY) AS sv_prev_7d
          FROM (
            SELECT asset_id, dt, argMax(value, computed_at) AS value
            FROM intraday_metrics
            WHERE metric_id = get_metric_id('social_volume')
              AND asset_id IN (SELECT asset_id FROM top_mcap)
              AND dt >= now() - INTERVAL 14 DAY
            GROUP BY asset_id, dt
          )
          GROUP BY asset_id
        )
      SELECT
        m.name AS slug,
        round(t.marketcap_usd) AS marketcap_usd,
        s.sv_last_7d,
        s.sv_prev_7d,
        round(s.sv_last_7d / nullIf(s.sv_prev_7d, 0) - 1, 3) AS sv_change
      FROM top_mcap AS t
      INNER JOIN social AS s ON s.asset_id = t.asset_id
      INNER JOIN (SELECT asset_id, name FROM asset_metadata FINAL) AS m ON m.asset_id = t.asset_id
      WHERE s.sv_prev_7d >= 20
      ORDER BY sv_change DESC
      LIMIT 10

  The `WHERE s.sv_prev_7d >= 20` floor keeps assets with almost no mentions from topping
  a growth ranking. Swap the metric names to screen on anything else. Find a metric's
  name with `SELECT metric_id, name FROM metric_metadata FINAL WHERE name ILIKE
  '%inflow%'`. Its name in ClickHouse can differ from the API's (the API's
  `social_volume_total` is `social_volume` here).

  Returns `columns`, `column_types`, `rows` (arrays in column order), `row_count`,
  `truncated`, the ClickHouse `clickhouse_query_id` and the execution `summary`
  (rows and bytes read, elapsed time). ClickHouse stops producing rows soon after
  `max_rows`, so a truncated result does not tell how many rows the query has in total.
  """

  use Anubis.Server.Component, type: :tool

  require Logger

  alias Anubis.Server.Response
  alias Sanbase.Accounts.ActivityTracesConfig
  alias Sanbase.MCP.Dev.SQL
  alias Sanbase.RequestContext
  alias Sanbase.MCP.ToolError

  @default_max_rows 200
  @max_rows_limit 5_000
  # Caps the uncompressed result ClickHouse sends back, for very wide rows.
  @max_result_bytes 32 * 1024 * 1024

  def name(), do: "execute_sql"

  @impl true
  def annotations() do
    %{
      "title" => "Execute ClickHouse SQL",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:sql, :string,
      required: true,
      description: "The ClickHouse SQL query. Use `{{name}}` placeholders for values."
    )

    field(:parameters, :map,
      description: "Values for the `{{name}}` placeholders, e.g. {\"slug\": \"bitcoin\"}."
    )

    field(:max_rows, :integer,
      description:
        "Max rows to return (default #{@default_max_rows}, at most #{@max_rows_limit})."
    )
  end

  @impl true
  def execute(%{sql: sql} = params, frame) do
    user = frame.assigns.current_user
    parameters = Map.get(params, :parameters) || %{}
    max_rows = params |> Map.get(:max_rows) |> clamp_max_rows()

    log_query(user, sql)

    cond do
      String.trim(sql) == "" ->
        error(frame, ToolError.permanent("`sql` is empty."))

      not is_map(parameters) ->
        error(frame, ToolError.permanent("`parameters` must be an object."))

      true ->
        case SQL.run(sql, parameters, user, clickhouse_settings: result_limits(max_rows)) do
          {:ok, result} ->
            {:reply, Response.json(Response.tool(), format(result, max_rows)), frame}

          {:error, error} ->
            error(frame, "Query failed: #{error}")
        end
    end
  end

  # Limit the result in ClickHouse so a query without a LIMIT is not loaded in full.
  # Asking for one row more than `max_rows` shows whether there are more. With 'break'
  # ClickHouse stops at a block boundary, so it can send more rows than the limit (the
  # rest of the block). `format/2` trims them.
  defp result_limits(max_rows) do
    [
      max_result_rows: max_rows + 1,
      max_result_bytes: @max_result_bytes,
      result_overflow_mode: "break"
    ]
  end

  defp format(result, max_rows) do
    rows = Enum.take(result.rows, max_rows)

    %{
      columns: result.columns,
      column_types: result.column_types,
      rows: SQL.json_safe_rows(rows, result.column_types),
      row_count: length(rows),
      truncated: length(result.rows) > max_rows,
      clickhouse_query_id: result.clickhouse_query_id,
      summary: result.summary
    }
  end

  # The logger filter for users with hidden activity traces does not rewrite this line,
  # so leave the SQL out for them.
  defp log_query(user, sql) do
    if ActivityTracesConfig.hidden?(:hide_logger, RequestContext.current()) do
      Logger.info("[MCP Dev] User #{user.id} execute_sql")
    else
      Logger.info(
        "[MCP Dev] User #{user.id} execute_sql: #{inspect(String.slice(sql, 0, 2_000))}"
      )
    end
  end

  defp clamp_max_rows(n) when is_integer(n) and n > 0, do: min(n, @max_rows_limit)
  defp clamp_max_rows(_), do: @default_max_rows

  defp error(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}
end
