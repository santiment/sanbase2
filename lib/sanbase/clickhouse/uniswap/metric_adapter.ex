defmodule Sanbase.Clickhouse.Uniswap.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Utils.Transform, only: [maybe_sort: 3]
  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.Transfers.Erc20Transfers

  alias Sanbase.Utils.Config

  @aggregations [:sum]

  @timeseries_metrics []

  @histogram_metrics ["uniswap_top_claimers"]

  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :restricted} end)
  @free_metrics Enum.filter(@access_map, &match?({_, :free}, &1)) |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, &match?({_, :restricted}, &1))
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})
  @default_complexity_weight 0.3

  defp address_ordered_table(), do: Config.module_get(Erc20Transfers, :address_ordered_table)

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def histogram_data(
        "uniswap_top_claimers" = metric,
        %{slug: "uniswap"} = selector,
        from,
        to,
        interval,
        limit
      ) do
    query_struct = histogram_data_query(metric, selector, from, to, interval, limit)

    Sanbase.ChRepo.query_transform(query_struct, fn [address, value] ->
      %{address: address, value: value}
    end)
    |> maybe_add_balances(from, to)
    |> maybe_sort(:value, :desc)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, _selector, _from, _to, _opts) do
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
  def first_datetime(_metric, _slug) do
    {:ok, ~U[2020-09-14 00:00:00Z]}
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, _slug) do
    {:ok, Timex.now()}
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "1h",
       default_aggregation: :sum,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       required_selectors: [:slug],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight,
       is_deprecated: true,
       hard_deprecate_after: nil,
       docs: [
         %{
           link:
             "https://academy.santiment.net/metrics/deprecated-metrics/deprecated-uniswap-metrics"
         }
       ],
       is_label_fqn_metric: false
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "uniswap_top_claimers" ->
        {:ok, "Uniswap Top Claimers"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

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
    case slug do
      "uniswap" -> {:ok, @metrics}
      _ -> {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    {:ok, ["uniswap"]}
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  # Private functions
  defp maybe_add_balances({:ok, data}, _from, to) do
    addresses = Enum.map(data, & &1.address)

    {:ok, balances} = Sanbase.Balance.last_balance_before(addresses, "uniswap", to)

    data =
      Enum.map(data, fn %{address: address} = elem ->
        Map.put(elem, :balance, Map.get(balances, address))
      end)

    {:ok, data}
  end

  defp maybe_add_balances({:error, error}, _from, _to), do: {:error, error}

  defp histogram_data_query(
         "uniswap_top_claimers",
         %{slug: "uniswap"},
         from,
         to,
         _interval,
         limit
       ) do
    sql = """
    SELECT
      to AS address,
      amount AS value
    FROM (
      SELECT
        to,
        SUM(value)/1e18 AS amount
      FROM #{address_ordered_table()} FINAL
      PREWHERE
        assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = 'uniswap' LIMIT 1) AND
        from = '0x090d4613473dee047c3f2706764f49e0821d256e' AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY to
      ORDER BY amount DESC
      LIMIT {{limit}}
    )
    """

    params = %{from: from |> DateTime.to_unix(), to: to |> DateTime.to_unix(), limit: limit}

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
