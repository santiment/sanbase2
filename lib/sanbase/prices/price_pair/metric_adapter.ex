defmodule Sanbase.PricePair.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  alias Sanbase.PricePair

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :ohlc, :count]
  @default_aggregation :last

  @timeseries_metrics ["price_usd", "price_eth", "price_usdt", "price_btc"]
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
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts(opts)
    PricePair.timeseries_data(slug, quote_asset, from, to, interval, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, %{slug: slug}, from, to, interval, opts) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts(opts)

    PricePair.timeseries_data_per_slug(slug, quote_asset, from, to, interval, opts)
    |> maybe_apply_function(&rename_same_aliases(&1, slug))
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{slug: slug}, from, to, opts) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts(opts)
    PricePair.aggregated_timeseries_data(slug, quote_asset, from, to, update_opts(opts))
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, from, to, operator, threshold, opts) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts(opts)
    PricePair.slugs_by_filter(quote_asset, from, to, operator, threshold, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, from, to, direction, opts) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts(opts)
    PricePair.slugs_order(quote_asset, from, to, direction, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, %{slug: slug}) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts([])
    PricePair.first_datetime(slug, quote_asset, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, %{slug: slug}) do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts([])
    PricePair.last_datetime_computed_at(slug, quote_asset, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "1s",
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
  def human_readable_name(metric) do
    case metric do
      "price_usd" -> {:ok, "Price in USD"}
      "price_btc" -> {:ok, "Price in BTC"}
      "price_usdt" -> {:ok, "Price in USDT"}
      "price_eth" -> {:ok, "Price in ETH"}
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

  def available_metrics(%{slug: slug}) do
    cache_key = {__MODULE__, :has_price_data?, slug} |> Sanbase.Cache.hash()
    cache_key_with_ttl = {cache_key, 900}

    case Sanbase.Cache.get_or_store(cache_key_with_ttl, fn ->
           PricePair.available_quote_assets(slug)
         end) do
      {:ok, quote_assets} ->
        metrics =
          if("BTC" in quote_assets, do: ["price_btc"], else: []) ++
            if("USD" in quote_assets, do: ["price_usd"], else: []) ++
            if("USDT" in quote_assets, do: ["price_usdt"], else: []) ++
            if("ETH" in quote_assets, do: ["price_eth"], else: [])

        {:ok, metrics}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    cache_key = {__MODULE__, :slugs_with_prices} |> Sanbase.Cache.hash()
    Sanbase.Cache.get_or_store({cache_key, 600}, fn -> PricePair.available_slugs() end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    quote_asset = metric_to_quote_asset(metric)
    opts = update_opts([])

    Sanbase.Cache.get_or_store({__MODULE__, :available_slugs_for_metric, 600}, fn ->
      PricePair.available_slugs(quote_asset, opts)
    end)
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

  defp metric_to_quote_asset("price_btc"), do: "BTC"
  defp metric_to_quote_asset("price_usd"), do: "USD"
  defp metric_to_quote_asset("price_usdt"), do: "USDT"
  defp metric_to_quote_asset("price_eth"), do: "ETH"

  defp rename_same_aliases({result, result_slugs_mapset}, slug_or_slugs) do
    parameters_slugs_mapset = slug_or_slugs |> List.wrap() |> MapSet.new()

    if needs_renaming?(result_slugs_mapset, parameters_slugs_mapset) do
      result
      |> rename(parameters_slugs_mapset, result_slugs_mapset)
    else
      result
    end
  end

  defp needs_renaming?(mapset1, mapset2) do
    not MapSet.equal?(mapset1, mapset2)
  end

  defp rename(result, parameters_slugs_mapset, _result_slugs_mapset) do
    prefixes = Sanbase.Project.Multichain.prefix_mapping() |> Map.keys()

    # The logic for renaming is tightly coupled with the drawbacks of the SQL used.
    # The data is stored using cryptocompare asset name (like base_asset="ARB") but
    # at Santiment we can have many asset pointing to the same cryptocompare asset like
    # "arbitrum" and "arb-arbitrum"
    rename_or_add_mapping =
      Enum.reduce(parameters_slugs_mapset, [], fn param_slug, acc ->
        if String.starts_with?(param_slug, prefixes) do
          base_slug = String.split(param_slug, "-", parts: 2) |> List.last()

          if base_slug in parameters_slugs_mapset do
            [{:duplicate, _result_slug = base_slug, _duplicate_as = param_slug}] ++ acc
          else
            [{:rename, base_slug, param_slug}] ++ acc
          end
        else
          acc
        end
      end)

    Enum.reduce(rename_or_add_mapping, result, fn
      {:rename, old_slug, new_slug}, acc ->
        Enum.map(acc, fn %{data: data} = elem ->
          new_data = rename_slug_in_data(data, old_slug, new_slug)
          Map.put(elem, :data, new_data)
        end)

      {:duplicate, existing_slug, new_slug}, acc ->
        Enum.map(acc, fn %{data: data} = elem ->
          new_data = duplicate_slug_in_data(data, existing_slug, new_slug)
          Map.put(elem, :data, new_data)
        end)
    end)
  end

  defp rename_slug_in_data(data_list, old_slug, new_slug) do
    Enum.map(data_list, fn
      %{slug: ^old_slug} = elem -> Map.put(elem, :slug, new_slug)
      elem -> elem
    end)
  end

  defp duplicate_slug_in_data(data_list, old_slug, new_slug) do
    Enum.flat_map(data_list, fn
      %{slug: ^old_slug} = elem -> [elem, Map.put(elem, :slug, new_slug)]
      elem -> [elem]
    end)
  end
end
