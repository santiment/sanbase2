defmodule Sanbase.MCP.AssetsByMetricTool do
  @moduledoc """
  A powerful metrics-based project filtering and sorting tool that works with cryptocurrency assets
  based on their metrics and allows for ordered, paginated results.

  The tool allows for filtering assets by a metric and sorting them according to that same metric
  in ascending or descending metric, or just to sort the assets by a metric without filtering.

  This tool allows you to discover projects that meet specific criteria by analyzing their
  metrics over time periods. You can filter projects by absolute values (greater_than/less_than thresholds)
  or by percentage changes, or just sort projects by some metric.

  ## When to use vs other metric tools

  This tool scans the whole asset universe and returns one aggregated value per
  matching asset — use it for "which assets satisfy X" and "top N by X".
  Every response has `values`: one row per asset in ranking order with the
  ranked metric's value, plus any `value_metrics` asked for (e.g. the price
  change of each of the top 100 by market cap, in one call).
  It never returns a timeseries: for the values of a metric over time for
  already-known slugs use `fetch_metric_data_tool`. To check that a metric
  exists (or fix a mistyped metric/slug) use `metrics_and_assets_discovery_tool`.

  ## Use Cases
  - Get top 10 assets by marketcap, sorted in descending order
  - Get top 50 assets with highest dev_activity_1d
  - Find assets with price more than $10
  - Discover tokens whose price increased by more than 50% in the last 30 days
  - Screen for projects with market cap less than $100M
  - Identify assets that have dev_activity_1d decline by more than 20% in the past month

  ## Examples
  - Get projects that have a price_usd in the last 24 hours and it's greater_than $500. Get the first 20
    ordered by price_usd in descending order
    `{metric: "price_usd", operator: :greater_than, threshold: 500.0, from: "utc_now-24h", to: "utc_now", sort: "desc, page: 1, page_size: 20}`
  - Find projects whose price_usd today is 25% higher than 7 days ago, sorted by the highest percent increase in descending order. Get the first 100.
    `{metric: "price_usd", operator: :percent_up, threshold: 25.0, from: "utc_now-7d", to: "utc_now", sort: "desc", page: 1, page_size: 100}`
  - Projects with current market cap less_than $50M. Get 100 such projects, ordered by marketcap in descending order.
    `{metric: "marketcap_usd", operator: :less_than, threshold: 50000000.0, from: "utc_now-1d", to: "utc_now", sort: "desc", page: 1, page_size: 100}`

  Here is how the filtering works:
  - For absolute value operators - `greater_than` and `less_than` - fetch the `metric` for each asset in the interval
   `from`-`to`, aggregting it using the specified `aggregation` method (defaulting to the metric's default).
  - For percent change operators - `percent_up` and `percent_down` - fetch the `metric` for each asset
    in the interval `from-`to`, as well as in the same length interval immediately before `from`.
    The two resulting values are compared to calculate the percentage change.

  Some metrics like price_usd and marketcap_usd are aggregated with `LAST` aggregation by default,
  meaning that the last known value in the queried interval is used. For percent change, this means that
  the tool compares the last known price immediately before `from` and the last known price before `to`.
  Other metrics like transaction_volume_usd and social_volume_total (and most other volume metrics) are aggregated by
  default with SUM aggregation, meaning that the total combined sum in the queried interval is used. For these
  metrics length of the time window is vital. A common mistake is to try to check if the social_total_total for
  the last 5 minutes is greater_than some threshold. Five minutes is not enough for social volume to accumulate enough.
  In such scenarios use a longer time window like 1 day or more.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.{DataCatalog, Utils}

  @impl true
  def annotations do
    %{
      "title" => "Screen Assets by Metric",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  @max_page_size 100
  @max_filters 3
  @max_value_metrics 5
  @operators ~w(greater_than less_than percent_up percent_down)
  @aggregations ~w(min max sum first last avg)

  schema do
    field(:metric, :string,
      required: true,
      description: """
      The metric to use for screening projects. This determines what aspect of each project will be analyzed.
      Common metrics include: 'price_usd', 'marketcap_usd', 'volume_usd', 'dev_activity', 'social_volume', 'active_addresses'.
      Use the data catalog to discover all available metrics for comprehensive screening options.
      Discover the supported metrics with the metrics_and_assets_discovery_tool.
      """
    )

    field(:from, :string,
      required: true,
      description: """
      Start date/time for the analysis period. Defines the beginning of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-01-01T00:00:00Z") or relative time expressions
      (e.g., "utc_now-30d" for 30 days ago, "utc_now-1h" for 1 hour ago)
      Defaults to 30 days ago if not specified. Used with percentage operators to calculate change over time.
      """
    )

    field(:to, :string,
      required: true,
      description: """
      End date/time for the analysis period. Defines the end of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-12-31T23:59:59Z") or relative time expressions
      (e.g., "utc_now" for current time, "utc_now-1d" for yesterday). Defaults to current time if not specified.
      Must be after the 'from' date. Used with percentage operators to calculate change over the specified period.
      """
    )

    field(:operator, :enum,
      type: :string,
      values: ~w(greater_than less_than percent_up percent_down),
      required: false,
      description: """
      Comparison operator that determines how projects are filtered based on the metric and threshold.

      Absolute value operators (compare current values):
      - `greater_than` - Include projects where the aggregated metric value is greater than the threshold
      - `less_than` - Include projects where the aggregated metric value is less than the threshold

      Percentage change operators (compare change from 'from' to 'to' period):
      - `percent_up` - Include projects where the metric increased by more than the threshold percentage
      - `percent_down` - Include projects where the metric decreased by more than the threshold percentage


      If this parameter is not provided, the threshold parameter also must not be provided. If they are
      not provided, the tool will simply sort the assets and will do no filtering.

      Example: operator=percent_up, threshold=25.0 finds projects that gained more than 25%.
      """
    )

    field(:threshold, {:either, {:integer, :float}},
      required: false,
      description: """
      The numeric threshold value used for filtering projects. The meaning depends on the operator:

      For absolute operators (:greater_than, :less_than):
      - The actual metric value to compare against (e.g., 10.5 for price_usd greater_than $10.50)
      - Units match the metric (USD for price/market cap, count for addresses, etc.)

      For percentage operators (:percent_up, :percent_down):
      - The percentage change threshold (e.g., 25.0 for 25% change)
      - Always expressed as a positive number regardless of direction

      If this parameter is not provided, the operator parameter also must not be provided. If they are
      not provided, the tool will simply sort the assets and will do no filtering.

      Examples: threshold=50000000.0 with :less_than finds projects with market cap under $50M
      """
    )

    field(:aggregation, :enum,
      type: :string,
      values: ~w(min max sum first last avg),
      required: false,
      description: """
      Method for aggregating metric data over the specified time period. Determines how multiple data points
      within the time window are combined into a single value for comparison.

      Common aggregation methods:
      - "avg" - Average value over the period (default for most metrics)
      - "sum" - Total sum of values (useful for volume, transaction counts)
      - "max" - Maximum value in the period (highest price, peak activity)
      - "min" - Minimum value in the period (lowest price, minimum activity)
      - "last" - Most recent value in the period
      - "first" - Earliest value in the period

      If not specified, uses the metric's default aggregation, whichi is carefully selected based on the metric type.
      Some aggregations do not make sense for certain metrics (e.g., summing prices).
      If not specifically required, using the metric's default aggregation method is recommended.
      """
    )

    field(:page, :integer,
      required: true,
      description: """
      Page number for paginated results. Used to retrieve specific pages when the result set is large.
      Starts from 1 (first page). Combine with page_size to control how many results are returned per page.
      Useful when only the top 10, 20, 100, etc. assets are needed.
      """
    )

    field(:page_size, :integer,
      required: true,
      description: """
      Number of projects to return per page (max 100). Controls the size of each paginated response.
      """
    )

    field(:sort, :enum,
      type: :string,
      values: ~w(asc desc),
      required: true,
      description: """
      Sort order for the filtered results based on the aggregated metric values.
      - "asc" - Ascending order (lowest values first, e.g., cheapest prices first)
      - "desc" - Descending order (highest values first, e.g., most expensive prices first)

      Particularly useful when combined with pagination to get the top/bottom performers.
      Example: sort="desc" with price_usd shows highest-priced projects first.
      """
    )

    embeds_many :filters,
      description: """
      Extra filters on other metrics, combined with AND. The ranking still uses `metric`.
      Each filter uses the same `from`/`to` window as the ranking. At most #{@max_filters}.

      Example — the largest assets by market cap whose price fell more than 5%:
      `{metric: "marketcap_usd", sort: "desc", filters: [{metric: "price_usd", operator: "percent_down", threshold: 5}], ...}`

      Filters pick from the whole asset universe before ranking. To screen only the current
      top N (e.g. "which of the top 200 moved less than 1%"), rank without filters and read
      `value_metrics` instead.
      """ do
      field(:metric, :string, required: true, description: "Metric to filter on.")

      field(:operator, :enum,
        type: :string,
        values: ~w(greater_than less_than percent_up percent_down),
        required: true,
        description: "Same operators as the top-level `operator`."
      )

      field(:threshold, {:either, {:integer, :float}},
        required: true,
        description: "Same meaning as the top-level `threshold`."
      )

      field(:aggregation, :enum,
        type: :string,
        values: ~w(min max sum first last avg),
        required: false,
        description: "Defaults to the metric's default aggregation."
      )
    end

    field(:value_metrics, {:list, :string},
      required: false,
      description: """
      Metrics to return a value for, for every asset on the page (at most #{@max_value_metrics}).
      The ranked `metric` is always returned too. Values come back in `values`, one row per
      asset in ranking order, so no separate fetch_metric_data_tool calls are needed.
      Only metrics with `supports_many_slugs: true` can be used here.

      Example — top 100 by market cap with their 24h price change:
      `{metric: "marketcap_usd", sort: "desc", from: "utc_now-1d", to: "utc_now", value_metrics: ["price_usd"], value_aggregation: "percent_change", page: 1, page_size: 100}`
      """
    )

    field(:value_aggregation, :enum,
      type: :string,
      values: ~w(min max sum first last avg percent_change),
      required: false,
      description: """
      How each of `value_metrics` is aggregated over `from`-`to`. Defaults to each metric's
      default aggregation. `percent_change` is the change from the first to the last value
      in the window, in percent, computed by the tool — use it instead of computing changes
      yourself. The key in `values` is then `<metric>_percent_change`.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    with :ok <- validate_metric(params[:metric]),
         :ok <- validate_operator_threshold_pair(params[:operator], params[:threshold]),
         :ok <- validate_aggregation(params[:aggregation]),
         :ok <- validate_sort(params[:sort]),
         :ok <- validate_page(params[:page]),
         {:ok, _} <- Utils.validate_size(params[:page_size], 1, @max_page_size),
         :ok <- validate_time_range(params[:from], params[:to]),
         :ok <- validate_filters(params[:filters]),
         :ok <- validate_value_metrics(params[:value_metrics]),
         :ok <- validate_value_aggregation(params[:value_aggregation]) do
      do_execute(params, frame)
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp do_execute(
         %{metric: metric, from: from, to: to, page: page, page_size: page_size} = params,
         frame
       ) do
    with {:ok, metadata} <- Sanbase.Metric.metadata(metric) do
      aggregation = to_aggregation(Map.get(params, :aggregation), metadata.default_aggregation)

      operator = if operator = params[:operator], do: safe_existing_atom(operator)
      threshold = params[:threshold]

      # If there's no operator and threshold
      filters =
        if not is_nil(operator) and not is_nil(threshold) do
          [metric_filter(metric, from, to, aggregation, operator, threshold)]
        else
          []
        end

      filters = filters ++ extra_filters(params[:filters], from, to)

      pagination = %{page: page, page_size: page_size}

      # The aggregation is passed so the order and the returned values agree
      # when the caller asked for a non-default one.
      order_by = %{
        metric: metric,
        from: from,
        to: to,
        aggregation: aggregation,
        direction: Map.get(params, :sort, "asc")
      }

      args = %{
        selector: %{
          filters: filters,
          filters_combinator: "and",
          pagination: pagination,
          order_by: order_by
        }
      }

      case Sanbase.Project.ListSelector.projects(args) do
        {:ok, %{projects: projects, total_projects_count: total_projects_count}} ->
          slugs = Enum.map(projects, & &1.slug)

          result = %{
            assets: slugs,
            values: values(slugs, metric, aggregation, params),
            page: page,
            page_size: page_size,
            total_assets: total_projects_count
          }

          {:reply, Response.json(Response.tool(), result), frame}

        {:error, error} when is_binary(error) ->
          {:reply, Response.error(Response.tool(), error), frame}

        {:error, error} ->
          {:reply, Response.error(Response.tool(), inspect(error)), frame}
      end
    end
  end

  defp metric_filter(metric, from, to, aggregation, operator, threshold) do
    %{
      name: "metric",
      args: %{
        metric: metric,
        from: from,
        to: to,
        aggregation: aggregation,
        operator: operator,
        threshold: threshold
      }
    }
  end

  defp extra_filters(nil, _from, _to), do: []

  defp extra_filters(filters, from, to) do
    Enum.map(filters, fn filter ->
      {:ok, metadata} = Sanbase.Metric.metadata(filter.metric)
      aggregation = to_aggregation(filter[:aggregation], metadata.default_aggregation)
      operator = safe_existing_atom(filter.operator)
      metric_filter(filter.metric, from, to, aggregation, operator, filter.threshold)
    end)
  end

  defp to_aggregation(aggregation, default) when is_binary(aggregation),
    do: safe_existing_atom(aggregation) || default

  defp to_aggregation(_aggregation, default), do: default

  # One row per asset on the page, in ranking order. Only the page's slugs are
  # queried (at most @max_page_size), one aggregated query per metric.
  defp values([], _metric, _aggregation, _params), do: []

  defp values(slugs, metric, aggregation, params) do
    {from, to} = {to_datetime(params.from), to_datetime(params.to)}
    value_aggregation = params[:value_aggregation]

    columns =
      [{metric, aggregated_values(metric, slugs, from, to, aggregation)}] ++
        Enum.map(Enum.uniq(params[:value_metrics] || []), fn value_metric ->
          value_column(value_metric, slugs, from, to, value_aggregation)
        end)

    Enum.map(slugs, fn slug ->
      Enum.reduce(columns, %{slug: slug}, fn {key, values}, row ->
        Map.put(row, key, Map.get(values, slug))
      end)
    end)
  end

  defp value_column(metric, slugs, from, to, "percent_change") do
    first = aggregated_values(metric, slugs, from, to, :first)
    last = aggregated_values(metric, slugs, from, to, :last)

    changes =
      Map.new(slugs, fn slug -> {slug, percent_change(first[slug], last[slug])} end)

    {"#{metric}_percent_change", changes}
  end

  defp value_column(metric, slugs, from, to, value_aggregation) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    aggregation = to_aggregation(value_aggregation, metadata.default_aggregation)
    {metric, aggregated_values(metric, slugs, from, to, aggregation)}
  end

  defp percent_change(first, last)
       when is_number(first) and is_number(last) and first != 0,
       do: Float.round((last - first) / abs(first) * 100, 2)

  defp percent_change(_first, _last), do: nil

  # A failed lookup leaves the column empty (null values) rather than failing
  # the ranking, which the caller already has. Some metrics (social ones) do
  # not take a list of slugs; they can still be the ranked metric, so they are
  # fetched per slug.
  defp aggregated_values(metric, slugs, from, to, aggregation) do
    opts = [aggregation: aggregation]

    case Sanbase.Metric.aggregated_timeseries_data(metric, %{slug: slugs}, from, to, opts) do
      {:ok, %{} = values} ->
        values

      _ ->
        slugs
        |> Sanbase.Parallel.map(
          fn slug ->
            case Sanbase.Metric.aggregated_timeseries_data(metric, %{slug: slug}, from, to, opts) do
              {:ok, %{} = values} -> values
              _ -> %{}
            end
          end,
          max_concurrency: 10,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.filter(&is_map/1)
        |> Enum.reduce(%{}, &Map.merge/2)
    end
  end

  defp to_datetime("utc_now" <> _ = value),
    do: Sanbase.Utils.DateTime.utc_now_string_to_datetime!(value)

  defp to_datetime(value), do: Sanbase.Utils.DateTime.from_iso8601!(value)

  defp validate_filters(nil), do: :ok
  defp validate_filters([]), do: :ok

  defp validate_filters(filters) when is_list(filters) and length(filters) > @max_filters,
    do: {:error, "At most #{@max_filters} filters can be passed."}

  defp validate_filters(filters) when is_list(filters) do
    Enum.reduce_while(filters, :ok, fn filter, :ok ->
      result =
        cond do
          not DataCatalog.valid_metric?(filter[:metric]) ->
            {:error,
             "Filter metric '#{filter[:metric]}' mistyped or not supported. Use " <>
               "metrics_and_assets_discovery_tool to list available metrics."}

          filter[:operator] not in @operators ->
            {:error,
             "Invalid filter operator '#{filter[:operator]}'. Must be one of: " <>
               Enum.join(@operators, ", ")}

          not is_number(filter[:threshold]) ->
            {:error, "Filter on '#{filter[:metric]}' needs a numeric `threshold`."}

          true ->
            validate_aggregation(filter[:aggregation])
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp validate_filters(_), do: {:error, "`filters` must be a list."}

  defp validate_value_metrics(nil), do: :ok

  defp validate_value_metrics(metrics) when is_list(metrics) do
    many_slugs =
      for %{name: name, supports_many_slugs: true} <- DataCatalog.available_metrics(),
          do: name

    cond do
      length(metrics) > @max_value_metrics ->
        {:error, "At most #{@max_value_metrics} value_metrics can be passed."}

      bad = Enum.find(metrics, &(not DataCatalog.valid_metric?(&1))) ->
        {:error,
         "Value metric '#{bad}' mistyped or not supported. Use " <>
           "metrics_and_assets_discovery_tool to list available metrics."}

      bad = Enum.find(metrics, &(&1 not in many_slugs)) ->
        {:error,
         "Value metric '#{bad}' cannot be fetched for many assets at once " <>
           "(supports_many_slugs is false). Use fetch_metric_data_tool for it instead."}

      true ->
        :ok
    end
  end

  defp validate_value_metrics(_), do: {:error, "`value_metrics` must be a list of metric names."}

  defp validate_value_aggregation(nil), do: :ok
  defp validate_value_aggregation("percent_change"), do: :ok
  defp validate_value_aggregation(aggregation), do: validate_aggregation(aggregation)

  defp validate_aggregation(nil), do: :ok

  defp validate_aggregation(aggregation) when aggregation in @aggregations, do: :ok

  defp validate_aggregation(aggregation),
    do:
      {:error,
       "Invalid aggregation '#{aggregation}'. Must be one of: min, max, sum, first, last, avg"}

  defp validate_sort(sort) when sort in ~w(asc desc), do: :ok
  defp validate_sort(nil), do: {:error, "Sort is required"}
  defp validate_sort(sort), do: {:error, "Invalid sort '#{sort}'. Must be one of: asc, desc"}

  defp validate_page(page) when is_integer(page) and page >= 1, do: :ok
  defp validate_page(nil), do: {:error, "Page is required"}
  defp validate_page(_page), do: {:error, "Page must be an integer greater than or equal to 1"}

  defp validate_metric(metric) do
    if DataCatalog.valid_metric?(metric),
      do: :ok,
      else:
        {:error,
         "Metric '#{metric}' mistyped or not supported. Use metrics_and_assets_discovery_tool to list available metrics."}
  end

  defp validate_time_range(from, to) do
    with :ok <- validate_time_string(from, "from"),
         :ok <- validate_time_string(to, "to") do
      :ok
    end
  end

  defp validate_time_string("utc_now" <> _ = value, name) do
    case Sanbase.Utils.DateTime.utc_now_string_to_datetime(value) do
      {:ok, _dt} ->
        :ok

      {:error, _} ->
        {:error,
         "Invalid '#{name}' value: '#{value}'. Use 'utc_now' or 'utc_now-<interval>' (e.g., 'utc_now-30d')."}
    end
  end

  defp validate_time_string(value, name) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _dt, _} ->
        :ok

      _ ->
        {:error,
         "Invalid '#{name}' value: '#{value}'. Use ISO 8601 (e.g., '2024-01-01T00:00:00Z') or relative expressions (e.g., 'utc_now-30d')."}
    end
  end

  defp validate_time_string(_, name) do
    {:error, "'#{name}' is required and must be a string."}
  end

  defp validate_operator_threshold_pair(nil, nil), do: :ok

  defp validate_operator_threshold_pair(operator, threshold) do
    case {operator, threshold} do
      {nil, nil} ->
        :ok

      {bin, nil} when is_binary(bin) ->
        {:error,
         "Cannot provide `operator` threshold without also providing the `threshold` param"}

      {nil, num} when is_number(num) ->
        {:error,
         "Cannot provide `threshold` threshold without also providing the `operator` param"}

      _ ->
        :ok
    end
  end

  # Convert a client-supplied string to an atom WITHOUT creating new atoms.
  # Using String.to_atom/1 on tool params would let a caller exhaust the BEAM
  # atom table (DoS). Unknown values return nil and are handled by the caller.
  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
