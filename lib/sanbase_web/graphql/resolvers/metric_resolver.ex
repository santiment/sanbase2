defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, handle_graphql_error: 4, maybe_handle_graphql_error: 2]

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
    %{context: %{product_id: product_id, auth: %{subscription: subscription}}} = resolution

    case Metric.metadata(metric) do
      {:ok, metadata} ->
        access_restrictions = Restrictions.get({:metric, metric}, subscription, product_id)
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

  def timeseries_data(
        _root,
        %{from: from, to: to, interval: interval} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    transform =
      Map.get(args, :transform, %{type: "none"}) |> Map.update!(:type, &Inflex.underscore/1)

    with {:ok, selector} <- args_to_selector(args),
         metric = maybe_replace_metric(metric, selector),
         opts = selector_args_to_opts(args),
         {:ok, from, to, interval} <-
           calibrate(Metric, metric, selector, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, from} <-
           calibrate_transform_params(transform, from, to, interval),
         {:ok, result} <-
           Metric.timeseries_data(metric, selector, from, to, interval, opts),
         {:ok, result} <- apply_transform(transform, result),
         {:ok, result} <- fit_from_datetime(result, args) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    with {:ok, selector} <- args_to_selector(args),
         opts = selector_args_to_opts(args),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <- Metric.aggregated_timeseries_data(metric, selector, from, to, opts) do
      [%{value: value} | _] = result
      {:ok, value}
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

    with {:ok, selector} <- args_to_selector(args),
         true <- valid_histogram_args?(metric, args),
         {:ok, data} <- Metric.histogram_data(metric, selector, from, to, interval, limit),
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

  # gold and s-and-p-500 are present only in the intrday metrics table, not in asset_prices
  defp maybe_replace_metric("price_usd", %{slug: slug})
       when slug in ["gold", "s-and-p-500", "crude-oil"],
       do: "price_usd_5m"

  defp maybe_replace_metric(metric, _selector), do: metric

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

  # All histogram metrics except "all_spent_coins_cost" require `from` argument
  defp valid_histogram_args?(metric, args) do
    if metric != "all_spent_coins_cost" && !Map.get(args, :from) do
      {:error, "Missing required `from` argument"}
    else
      true
    end
  end
end
