defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, maybe_handle_graphql_error: 2]

  import Sanbase.Metric.Selector, only: [args_to_selector: 1, args_to_raw_selector: 1]
  import SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Metric
  alias Sanbase.Billing.Plan.Restrictions
  alias Sanbase.Billing.Plan.AccessChecker

  require Logger

  @datapoints 300

  def get_metric(_root, %{metric: metric}, _resolution) do
    case Metric.has_metric?(metric) do
      true -> {:ok, %{metric: metric}}
      {:error, error} -> {:error, error}
    end
  end

  def get_available_metrics(
        _root,
        %{product: product, plan: plan},
        _resolution
      ) do
    product = product |> Atom.to_string() |> String.upcase()
    {:ok, AccessChecker.get_available_metrics_for_plan(product, plan)}
  end

  def get_available_metrics(_root, _args, _resolution), do: {:ok, Metric.available_metrics()}

  def get_available_slugs(_root, _args, %{source: %{metric: metric}}),
    do: Metric.available_slugs(metric)

  def get_human_readable_name(_root, _args, %{source: %{metric: metric}}),
    do: Metric.human_readable_name(metric)

  def get_metadata(%{}, _args, %{source: %{metric: metric}} = resolution) do
    %{context: %{product_id: product_id, auth: %{plan: plan}}} = resolution

    case Metric.metadata(metric) do
      {:ok, metadata} ->
        access_restrictions = Restrictions.get({:metric, metric}, plan, product_id)
        {:ok, Map.merge(access_restrictions, metadata)}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", %{metric: metric}, error)}
    end
  end

  def timeseries_data_complexity(_root, args, resolution) do
    complexity = SanbaseWeb.Graphql.Complexity.from_to_interval(args, 2, resolution)
    {:ok, complexity |> Sanbase.Math.to_integer()}
  end

  def available_since(_root, args, %{source: %{metric: metric}}) do
    with {:ok, selector} <- args_to_selector(args),
         {:ok, first_datetime} <- Metric.first_datetime(metric, selector) do
      {:ok, first_datetime}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Available Since",
        %{metric: metric, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def last_datetime_computed_at(_root, args, %{source: %{metric: metric}}) do
    with {:ok, selector} <- args_to_selector(args) do
      Metric.last_datetime_computed_at(metric, selector)
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Last Datetime Computed At",
        %{metric: metric, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def timeseries_data(_root, args, %{source: %{metric: metric}} = resolution) do
    requested_fields = requested_fields(resolution)
    fetch_timeseries_data(metric, args, requested_fields, :timeseries_data)
  end

  def timeseries_data(_root, args, %{source: %{metric: metric}} = resolution) do
    requested_fields = requested_fields(resolution)
    fetch_timeseries_data(metric, args, requested_fields, :timeseries_data)
  end

  def timeseries_data_per_slug(_root, args, %{source: %{metric: metric}} = resolution) do
    requested_fields = requested_fields(resolution)
    fetch_timeseries_data(metric, args, requested_fields, :timeseries_data_per_slug)
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} = selector_args_to_opts(args),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <- Metric.aggregated_timeseries_data(metric, selector, from, to, opts) do
      {:ok, Map.values(result) |> List.first()}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def histogram_data(
        _root,
        args,
        %{source: %{metric: metric}}
      ) do
    %{to: to, interval: interval, limit: limit} = args
    # from datetime arg is not required for `all_spent_coins_cost` metric which calculates
    # the histogram for all time.
    from = Map.get(args, :from, nil)
    interval = transform_interval(metric, interval)

    with true <- valid_histogram_args?(metric, args),
         {:ok, selector} <- args_to_selector(args),
         {:ok, data} <-
           Metric.histogram_data(metric, selector, from, to, interval, limit),
         {:ok, data} <- maybe_enrich_with_labels(metric, data) do
      {:ok, %{values: %{data: data}}}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def table_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    with {:ok, selector} <- args_to_selector(args),
         {:ok, data} <- Metric.table_data(metric, selector, from, to) do
      {:ok, data}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  # Private functions

  # timeseries_data and timeseries_data_per_slug are processed and fetched in
  # exactly the same way. The only difference is the function that is called
  # from the Metric module.
  defp fetch_timeseries_data(metric, args, requested_fields, function) do
    transform =
      Map.get(args, :transform, %{type: "none"})
      |> Map.update!(:type, &Inflex.underscore/1)

    with {:ok, selector} <- args_to_selector(args),
         {:ok, opts} <- selector_args_to_opts(args),
         true <- valid_timeseries_selection?(requested_fields, args),
         {:ok, from, to, interval} <-
           transform_datetime_params(selector, metric, transform, args),
         {:ok, result} <- apply(Metric, function, [metric, selector, from, to, interval, opts]),
         {:ok, result} <- apply_transform(transform, result),
         {:ok, result} <- fit_from_datetime(result, args) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  defp transform_datetime_params(selector, metric, transform, args) do
    %{from: from, to: to, interval: interval} = args

    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    with {:ok, from, to, interval} <-
           calibrate(Metric, metric, selector, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, from} <-
           calibrate_transform_params(transform, from, to, interval) do
      {:ok, from, to, interval}
    end
  end

  defp maybe_enrich_with_labels("eth2_top_stakers", data), do: {:ok, data}

  defp maybe_enrich_with_labels(_metric, [%{address: address} | _] = data)
       when is_binary(address) do
    addresses = Enum.map(data, & &1.address) |> Enum.uniq()
    {:ok, labels} = Sanbase.Clickhouse.Label.get_address_labels("ethereum", addresses)

    labeled_data =
      Enum.map(data, fn %{address: address} = elem ->
        address_labels = Map.get(labels, address, []) |> Enum.map(& &1.name)
        Map.put(elem, :labels, address_labels)
      end)

    {:ok, labeled_data}
  end

  defp maybe_enrich_with_labels(_metric, data), do: {:ok, data}

  defp calibrate_transform_params(%{type: "none"}, from, _to, _interval),
    do: {:ok, from}

  defp calibrate_transform_params(
         %{type: "moving_average", moving_average_base: base},
         from,
         _to,
         interval
       ) do
    shift_by_sec = base * Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  defp calibrate_transform_params(%{type: type}, from, _to, interval)
       when type in [
              "changes",
              "consecutive_differences",
              "percent_change",
              "cumulative_percent_change"
            ] do
    shift_by_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  defp apply_transform(%{type: "none"}, data), do: {:ok, data}

  defp apply_transform(%{type: "moving_average", moving_average_base: base}, data) do
    Sanbase.Math.simple_moving_average(data, base, value_key: :value)
  end

  defp apply_transform(%{type: type}, data) when type in ["changes", "consecutive_differences"] do
    result =
      Stream.chunk_every(data, 2, 1, :discard)
      |> Enum.map(fn [%{value: previous}, %{value: current, datetime: datetime}] ->
        %{
          datetime: datetime,
          value: current - previous
        }
      end)

    {:ok, result}
  end

  defp apply_transform(%{type: type}, data) when type in ["percent_change"] do
    result =
      Stream.chunk_every(data, 2, 1, :discard)
      |> Enum.map(fn [%{value: previous}, %{value: current, datetime: datetime}] ->
        %{
          datetime: datetime,
          value: Sanbase.Math.percent_change(previous, current)
        }
      end)

    {:ok, result}
  end

  defp apply_transform(%{type: type}, data) when type in ["cumulative_percent_change"] do
    cumsum =
      data
      |> Enum.scan(fn %{value: current} = elem, %{value: previous} ->
        %{elem | value: current + previous}
      end)

    apply_transform(%{type: "percent_change"}, cumsum)
  end

  defp transform_interval("all_spent_coins_cost", interval) do
    Enum.max([Sanbase.DateTimeUtils.str_to_days(interval), 1])
    |> to_string
    |> Kernel.<>("d")
  end

  defp transform_interval(_, interval), do: interval

  @metrics_allowed_missing_from ["all_spent_coins_cost", "eth2_staked_amount_per_label"]
  # All histogram metrics except "all_spent_coins_cost" require `from` argument
  defp valid_histogram_args?(metric, args) do
    if metric in @metrics_allowed_missing_from or Map.get(args, :from) do
      true
    else
      {:error, "Missing required `from` argument"}
    end
  end

  defp valid_timeseries_selection?(requested_fields, args) do
    aggregation = Map.get(args, :aggregation, nil)
    value_requested? = MapSet.member?(requested_fields, "value")
    value_ohlc_requested? = MapSet.member?(requested_fields, "valueOhlc")

    cond do
      aggregation == :ohlc && value_requested? ->
        {:error, "Field value shouldn't be selected when using aggregation ohlc"}

      value_ohlc_requested? && aggregation != :ohlc ->
        {:error, "Selected field valueOhlc works only with aggregation ohlc"}

      value_requested? and value_ohlc_requested? ->
        {:error, "Cannot select value and valueOhlc fields at the same time"}

      true ->
        true
    end
  end
end
