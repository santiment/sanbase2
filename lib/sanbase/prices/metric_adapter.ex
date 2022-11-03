defmodule Sanbase.Price.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  alias Sanbase.Price

  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :ohlc]
  @default_aggregation :last

  @timeseries_metrics ["price_usd", "price_btc", "volume_usd", "marketcap_usd"]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})
  @default_complexity_weight 0.3

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{slug: slug}, from, to, interval, opts) do
    Price.timeseries_metric_data(slug, metric, from, to, interval, update_opts(opts))
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, %{slug: slug}, from, to, interval, opts) do
    Price.timeseries_metric_data_per_slug(slug, metric, from, to, interval, update_opts(opts))
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{slug: slug}, from, to, opts) do
    Price.aggregated_metric_timeseries_data(slug, metric, from, to, update_opts(opts))
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, from, to, operator, threshold, opts) do
    Price.slugs_by_filter(metric, from, to, operator, threshold, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, from, to, direction, opts) do
    Price.slugs_order(metric, from, to, direction, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(_metric, %{slug: slug}) do
    Price.first_datetime(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, %{slug: slug}) do
    Price.last_datetime_computed_at(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "5m",
       default_aggregation: @default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       required_selectors: [:slug],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "price_usd" -> {:ok, "Price in USD"}
      "price_btc" -> {:ok, "Price in BTC"}
      "price_eth" -> {:ok, "Price in ETH"}
      "marketcap_usd" -> {:ok, "Marketcap in USD"}
      "volume_usd" -> {:ok, "Volume in USd"}
    end
  end

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

  def available_metrics(%{slug: "TOTAL_ERC20"}), do: @metrics

  def available_metrics(%{slug: slug}) do
    cache_key = {__MODULE__, :has_price_data?, slug} |> Sanbase.Cache.hash()
    cache_key_with_ttl = {cache_key, 600}

    case Sanbase.Cache.get_or_store(cache_key_with_ttl, fn -> Price.has_data?(slug) end) do
      {:ok, true} -> {:ok, @metrics}
      {:ok, false} -> {:ok, []}
      {:error, error} -> {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    cache_key = {__MODULE__, :slugs_with_prices} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn -> Price.available_slugs() end)
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
  defp update_opts(opts) do
    Keyword.update(opts, :aggregation, @default_aggregation, &(&1 || @default_aggregation))
  end
end
