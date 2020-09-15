defmodule Sanbase.Clickhouse.TopHolders.MetricAdapter do
  @moduledoc ~s"""
  Adapter for pluging top holders metrics in the getMetric API
  """
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Clickhouse.TopHolders.SqlQuery
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  alias Sanbase.Model.Project

  alias Sanbase.ClickhouseRepo

  @supported_infrastructures ["ETH", "BNB", "BEP2"]

  @default_complexity_weight 0.3

  def supported_infrastructures(), do: @supported_infrastructures

  @infrastructure_to_table %{
    "ETH" => "eth_top_holders",
    "BNB" => "bnb_top_holders",
    "BEP2" => "bnb_top_holders"
  }

  @infrastructure_to_blockchain %{
    "ETH" => "ethereum",
    "BNB" => "binance-coin",
    "BEP2" => "binance-coin"
  }

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

  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :restricted} end)
  @min_plan_map Enum.into(@metrics, %{}, fn metric ->
                  {metric, %{"SANAPI" => :free, "SANBASE" => :free}}
                end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Enum.map(&elem(&1, 0))

  @default_holders_count 10

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(
        metric,
        %{slug: slug} = selector,
        from,
        to,
        interval,
        opts
      ) do
    aggregation = Keyword.get(opts, :aggregation, nil) || :last
    count = Map.get(selector, :holders_count, @default_holders_count)

    with {:ok, contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         true <- chain_supported?(infr, slug, metric) do
      table = Map.get(@infrastructure_to_table, infr)
      blockchain = Map.get(@infrastructure_to_blockchain, infr)

      {query, args} =
        timeseries_data_query(
          metric,
          table,
          contract,
          blockchain,
          count,
          from,
          to,
          interval,
          decimals,
          aggregation
        )

      ClickhouseRepo.query_transform(query, args, fn [timestamp, value] ->
        %{datetime: DateTime.from_unix!(timestamp), value: value}
      end)
    end
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(_, %{slug: _slug}, _from, _to, _opts) do
    {:error, "Aggregated timeseries data is not implemented for Top Holders."}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(_metric, _from, _to, _operator, _threshold, _opts) do
    {:error, "Slugs filtering is not implemented for Top Holders."}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(_metric, _from, _to, _direction, _opts) do
    {:error, "Slugs ordering is not implemented for Top Holders."}
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) when metric in @metrics do
    data_type = if metric in @timeseries_metrics, do: :timeseries, else: :histogram

    {:ok,
     %{
       metric: metric,
       min_interval: "1d",
       default_aggregation: @default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: [:slug, :holders_count],
       data_type: data_type,
       complexity_weight: @default_complexity_weight
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
  def available_metrics(%{slug: slug}) do
    with %Project{} = project <- Project.by_slug(slug, only_preload: [:infrastructure]),
         {:ok, infr} <- Project.infrastructure_real_code(project) do
      if infr in @supported_infrastructures and Project.has_contract_address?(project) do
        # Until we have Binance exchange addresses remove exchange metrics for it.
        case infr in ["BNB", "BEP2"] do
          true -> {:ok, @metrics |> Enum.reject(&String.contains?(&1, "exchange"))}
          false -> {:ok, @metrics}
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
      table = Map.get(@infrastructure_to_table, infr)
      {query, args} = first_datetime_query(table, contract)

      ClickhouseRepo.query_transform(query, args, fn [timestamp] ->
        DateTime.from_unix!(timestamp)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, %{slug: slug}) do
    with {:ok, contract, _decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         true <- chain_supported?(infr, slug, metric) do
      table = Map.get(@infrastructure_to_table, infr)
      {query, args} = last_datetime_computed_at_query(table, contract)

      ClickhouseRepo.query_transform(query, args, fn [timestamp] ->
        DateTime.from_unix!(timestamp)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    cache_key = {__MODULE__, :available_slugs} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 1800}, fn ->
      result =
        Project.List.projects(preload: [:infrastructure])
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
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

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
end
