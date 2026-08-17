defmodule Sanbase.Metric.MetricReplace do
  @moduledoc ~s"""
  Rewrite price/volume metrics for non-crypto assets to their `_5m` counterparts.

  Non-crypto assets have two data sources. `asset_prices_v3` holds the data keyed
  by source (hyperliquid, cryptocompare), while the older values computed by the
  bigdata team live in `intraday_metrics` under `price_usd_5m`/`volume_usd_5m`.
  So the metric is rewritten only when no explicit source picks `asset_prices_v3`.
  """

  # Sources present in `asset_prices_v3` - asking for them means asking for that
  # table, so the metric must be left alone.
  @sources_without_replace ~w(hyperliquid cryptocompare)

  @replacements %{"price_usd" => "price_usd_5m", "volume_usd" => "volume_usd_5m"}

  def maybe_replace_metric(metric, selector) when is_binary(metric) do
    case Map.get(@replacements, metric) do
      nil -> metric
      replacement -> if replace?(selector), do: replacement, else: metric
    end
  end

  def maybe_replace_metrics([_ | _] = metrics_list, selector) do
    if replace?(selector) do
      Enum.map(metrics_list, &maybe_replace_metric(&1, selector))
    else
      metrics_list
    end
  end

  def maybe_replace_metrics(metrics_list, _selector), do: metrics_list

  defp replace?(%{slug: slug} = selector) when is_binary(slug) do
    Map.get(selector, :source) not in @sources_without_replace and
      Sanbase.AvailableSlugs.non_crypto_asset_slug?(slug)
  end

  defp replace?(_selector), do: false
end
