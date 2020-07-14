defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias Sanbase.Metric
  alias Sanbase.Billing.Plan.Restrictions
  alias Sanbase.Billing.Plan.AccessChecker

  require Logger

  @datapoints 300
  @available_slugs_module if Mix.env() == :test,
                            do: Sanbase.DirectAvailableSlugs,
                            else: Sanbase.AvailableSlugs

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
        {:error, handle_graphql_error("metadata", metric, error, description: "metric")}
    end
  end

  def timeseries_data_complexity(_root, args, resolution) do
    complexity = SanbaseWeb.Graphql.Complexity.from_to_interval(args, 2, resolution)
    {:ok, complexity |> Sanbase.Math.to_integer()}
  end

  def available_since(_root, args, %{source: %{metric: metric}}) do
    selector = to_selector(args)

    case valid_selector?(selector) do
      true -> Metric.first_datetime(metric, selector)
      {:error, error} -> {:error, error}
    end
  end

  def last_datetime_computed_at(_root, args, %{source: %{metric: metric}}) do
    selector = to_selector(args)

    case valid_selector?(selector) do
      true -> Metric.last_datetime_computed_at(metric, selector)
      {:error, error} -> {:error, error}
    end
  end

  def timeseries_data(
        _root,
        %{from: from, to: to, interval: interval} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    transform =
      Map.get(args, :transform, %{type: "none"}) |> Map.update!(:type, &Inflex.underscore/1)

    selector = to_selector(args)
    metric = maybe_replace_metric(metric, selector)
    opts = args_to_opts(args)

    with true <- valid_selector?(selector),
         {:ok, from, to, interval} <-
           calibrate_interval(Metric, metric, selector, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, from} <-
           calibrate_transform_params(transform, from, to, interval),
         {:ok, result} <-
           Metric.timeseries_data(metric, selector, from, to, interval, opts),
         {:ok, result} <- apply_transform(transform, result),
         {:ok, result} <- fit_from_datetime(result, args) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, selector, error)}
    end
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)
    selector = to_selector(args)
    opts = args_to_opts(args)

    with true <- valid_selector?(selector),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <-
           Metric.aggregated_timeseries_data(metric, selector, from, to, opts) do
      # This requires internal rework - all aggregated_timeseries_data queries must return the same format
      case result do
        value when is_number(value) ->
          {:ok, value}

        [%{value: value}] ->
          {:ok, value}

        %{} = map ->
          value = Map.values(map) |> hd
          {:ok, value}

        _ ->
          {:ok, nil}
      end
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, selector, error)}
    end
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
    selector = to_selector(args)

    with true <- valid_selector?(selector),
         true <- valid_histogram_args?(metric, args),
         {:ok, data} <- Metric.histogram_data(metric, selector, from, to, interval, limit) do
      {:ok, %{values: %{data: data}}}
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, selector, error)}
    end
  end

  # Private functions

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

  defp valid_selector?(%{slug: slug}) when is_binary(slug) do
    case @available_slugs_module.valid_slug?(slug) do
      true -> true
      false -> {:error, "The slug #{inspect(slug)} is not an existing slug."}
    end
  end

  defp valid_selector?(%{} = map) when map_size(map) == 0,
    do:
      {:error,
       "The selector must have at least one field provided." <>
         "The available selector fields for a metric are listed in the metadata's availableSelectors field."}

  defp valid_selector?(_), do: true

  defp to_selector(%{slug: slug}), do: %{slug: slug}
  defp to_selector(%{word: word}), do: %{word: word}
  defp to_selector(%{selector: %{} = selector}), do: selector
  defp to_selector(_), do: %{}

  # Convert the args to opts that the Metric module recognizes
  defp args_to_opts(args) when is_map(args) do
    opts = [aggregation: Map.get(args, :aggregation, nil)]

    with selector when is_map(selector) <- args[:selector],
         {map, _rest} when map_size(map) > 0 <- Map.split(selector, [:owner, :label]) do
      [additional_filters: Keyword.new(map)] ++ opts
    else
      _ ->
        opts
    end
  end
end
