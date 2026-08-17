defmodule Sanbase.Hyperliquid.Bbo.MetricAdapter do
  @moduledoc ~s"""
  Serve `price_usd` from the Hyperliquid BBO book instead of `asset_prices_v3`.

  Reached only when the selector carries `source: "hyperliquid"` - see
  `Sanbase.Metric.get_module/2`. The value is `weighted_mid_price`, the
  size-weighted midpoint of the best bid/ask snapshot in the bucket.

  Hyperliquid provides a quote, not a computed marketcap or volume, so
  `price_usd` is the only metric here.
  """

  @behaviour Sanbase.Metric.Behaviour

  alias Sanbase.Hyperliquid.Bbo.BboPrices
  alias Sanbase.Project.SourceSlugMapping

  @source "hyperliquid"

  # A BBO bucket holds the last snapshot in it, so `last` is the only aggregation
  # that does not misrepresent the data.
  @aggregations [:last]
  @default_aggregation :last

  @timeseries_metrics ["price_usd"]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, [:slug]})
  @default_complexity_weight 0.3

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_metric), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_metric), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data("price_usd", %{slug: slug}, from, to, interval, _opts) do
    BboPrices.price_usd_timeseries_data(slug, from, to, interval)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug("price_usd", %{slug: slug}, from, to, interval, _opts) do
    with {:ok, data} <- BboPrices.price_usd_timeseries_data(slug, from, to, interval) do
      {:ok, Enum.map(data, &%{datetime: &1.datetime, data: [%{slug: slug, value: &1.value}]})}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data("price_usd", %{slug: slug}, from, to, _opts) do
    # A single bucket spanning the whole range - its value is the last snapshot
    # in the range, which is the only aggregation this data supports.
    interval = "#{DateTime.diff(to, from)}s"

    with {:ok, data} <- BboPrices.price_usd_timeseries_data(slug, from, to, interval) do
      value = data |> List.last() |> then(&(&1 && &1.value))
      {:ok, %{slug => value}}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime("price_usd", %{slug: slug}, _opts), do: BboPrices.first_datetime(slug)

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at("price_usd", %{slug: slug}) do
    BboPrices.last_datetime_computed_at(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       # The websocket scraper writes every book update
       min_interval: "1s",
       stabilization_period: "0h",
       can_mutate: false,
       default_aggregation: @default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       required_selectors: [:slug],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight,
       is_label_fqn_metric: false,
       is_deprecated: false,
       docs: [%{link: "https://academy.santiment.net/metrics/price"}],
       hard_deprecate_after: nil,
       status: "released"
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name("price_usd"), do: {:ok, "Price in USD"}

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
  def available_metrics(%{slug: slug}, _opts) do
    case slug in available_slugs!() do
      true -> {:ok, @metrics}
      false -> {:ok, []}
    end
  end

  def available_metrics(_selector, _opts), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: {:ok, available_slugs!()}

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric, _opts) when metric in @metrics, do: available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_non_crypto_asset_slugs(_metric, [], _opts), do: {:ok, []}

  def available_non_crypto_asset_slugs(metric, slugs, _opts) when metric in @metrics do
    {:ok, Enum.filter(slugs, &(&1 in available_slugs!()))}
  end

  def available_non_crypto_asset_slugs(_metric, _slugs, _opts), do: {:ok, []}

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

  # The projects and non-crypto assets with a `hyperliquid` source slug mapping.
  defp available_slugs!() do
    Sanbase.Cache.get_or_store({{__MODULE__, :available_slugs}, 600}, fn ->
      @source
      |> SourceSlugMapping.get_source_slug_mappings(return: :all)
      |> Enum.map(fn {_source_slug, slug} -> slug end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()
    end)
  end
end
