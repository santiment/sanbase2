defmodule Sanbase.Clickhouse.TopHolders.MetricAdapter do
  @moduledoc ~s"""
  Adapter for pluging top holders metrics in the getMetric API
  """
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Clickhouse.TopHolders.SqlQuery

  import Sanbase.Utils.Transform,
    only: [maybe_fill_gaps_last_seen: 2, maybe_unwrap_ok_value: 1]

  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.Project

  alias Sanbase.ClickhouseRepo

  @supported_infrastructures ["ETH"]

  @default_complexity_weight 0.3

  def supported_infrastructures(), do: @supported_infrastructures

  @infrastructure_to_table %{"ETH" => "eth_top_holders_daily"}

  @infrastructure_to_blockchain %{"ETH" => "ethereum"}

  @default_aggregation :last
  @aggregations [:last, :min, :max, :first]

  @timeseries_metrics [
    "amount_in_top_holders",
    "amount_in_exchange_top_holders",
    "amount_in_non_exchange_top_holders"
  ]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric ->
                  {metric, %{"SANAPI" => "FREE", "SANBASE" => "FREE"}}
                end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :restricted} end)
  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})
  @default_holders_count 10

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{slug: slug} = selector, from, to, interval, opts) do
    with {:ok, contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         true <- chain_supported?(infr, slug, metric),
         {:ok, params} <-
           timeseries_data_params(selector, contract, infr, from, to, interval, decimals, opts) do
      result =
        timeseries_data_query(metric, params)
        |> ClickhouseRepo.query_transform(fn [timestamp, value, has_changed] ->
          %{datetime: DateTime.from_unix!(timestamp), value: value, has_changed: has_changed}
        end)

      case result do
        {:ok, list} -> {:ok, gap_fill_last_known(list)}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp gap_fill_last_known(list) do
    # Do not gap fill the leading missing values
    list = Enum.drop_while(list, &(&1.has_changed == 0))

    {:ok, list} = maybe_fill_gaps_last_seen({:ok, list}, :value)
    list
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{slug: _slug}, _from, _to, _opts) do
    not_implemented_function_for_metric_error("aggregated_timeseries_data", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, _from, _to, _operator, _threshold, _opts) do
    not_implemented_function_for_metric_error("slugs_by_filter", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, _from, _to, _direction, _opts) do
    not_implemented_function_for_metric_error("slugs_order", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) when metric in @metrics do
    data_type = if metric in @timeseries_metrics, do: :timeseries, else: :histogram

    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "1d",
       can_mutate: true,
       default_aggregation: @default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: [:slug, :holders_count],
       required_selectors: [:slug],
       data_type: data_type,
       is_timebound: false,
       complexity_weight: @default_complexity_weight,
       is_deprecated: false,
       hard_deprecate_after: nil,
       docs: [],
       is_label_fqn_metric: false
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "amount_in_top_holders" -> {:ok, "Top Holders Balance"}
      "amount_in_exchange_top_holders" -> {:ok, "Exchange Top Holders Balance"}
      "amount_in_non_exchange_top_holders" -> {:ok, "Non-Exchange Top Holders Balance"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{address: _address}), do: []

  def available_metrics(%{contract_address: contract_address}) do
    Sanbase.Metric.Utils.available_metrics_for_contract(__MODULE__, contract_address)
  end

  def available_metrics(%{slug: slug}) do
    with %Project{} = project <- Project.by_slug(slug, preload: [:infrastructure]),
         {:ok, infr} <- Project.infrastructure_real_code(project) do
      if infr in @supported_infrastructures and Project.has_contract_address?(project) do
        # Until we have Binance exchange addresses remove exchange metrics for it.
        case infr in ["ETH"] do
          true -> {:ok, @metrics}
          false -> {:ok, @metrics |> Enum.reject(&String.contains?(&1, "exchange"))}
        end
      else
        {:ok, []}
      end
    else
      {:error, {:missing_contract, _}} -> {:ok, []}
      error -> error
    end
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, %{slug: slug}) do
    with {:ok, contract, _decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         true <- chain_supported?(infr, slug, metric) do
      table = to_table(contract, infr)
      query_struct = first_datetime_query(table, contract)

      ClickhouseRepo.query_transform(query_struct, fn [timestamp] ->
        DateTime.from_unix!(timestamp)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, %{slug: slug}) do
    with {:ok, contract, _decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         true <- chain_supported?(infr, slug, metric) do
      table = to_table(contract, infr)
      _query_struct = first_datetime_query(table, contract)
      query_struct = last_datetime_computed_at_query(table, contract)

      ClickhouseRepo.query_transform(query_struct, fn [timestamp] ->
        DateTime.from_unix!(timestamp)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    cache_key = {__MODULE__, :available_slugs} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 1800}, &projects_with_supported_infrastructure/0)
  end

  defp projects_with_supported_infrastructure() do
    result =
      Project.List.projects(preload: [:infrastructure, :contract_addresses])
      |> Enum.filter(fn project ->
        case Project.infrastructure_real_code(project) do
          {:ok, infr_code} ->
            infr_code in @supported_infrastructures and
              Project.has_contract_address?(project)

          _ ->
            false
        end
      end)
      |> Enum.map(& &1.slug)

    {:ok, result}
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: []

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  # Private functions
  defp chain_supported?(infr, _slug, _metric_) when infr in @supported_infrastructures,
    do: true

  defp chain_supported?(_infr, slug, metric) do
    {:error, "The metric #{metric} is not supported for #{slug}"}
  end

  defp timeseries_data_params(selector, contract, infr, from, to, interval, decimals, opts) do
    params = %{
      contract: contract,
      blockchain: Map.get(@infrastructure_to_blockchain, infr),
      table: to_table(contract, infr),
      count: Map.get(selector, :holders_count, @default_holders_count),
      from: from,
      to: to,
      interval: interval,
      decimals: decimals,
      aggregation: Keyword.get(opts, :aggregation, nil) || :last,
      include_labels: Keyword.get(opts, :additional_filters, [])[:label]
    }

    {:ok, params}
  end

  defp to_table(contract, infrastructure) do
    table = Map.get(@infrastructure_to_table, infrastructure)

    cond do
      contract == "ETH" and infrastructure == "ETH" -> table
      contract != "ETH" and infrastructure == "ETH" -> "erc20_top_holders_daily"
      true -> table
    end
  end
end
