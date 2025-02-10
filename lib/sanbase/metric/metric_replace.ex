defmodule Sanbase.Metric.MetricReplace do
  @moduledoc false
  @slugs_with_changed_price_metric ~w(gold s-and-p-500 crude-oil dxy)
  @slugs_with_changed_volume_metric ~w(fbtc btco hodl gbtc arkb bitb ibit)

  @slugs_with_changed_metric @slugs_with_changed_price_metric ++
                               @slugs_with_changed_volume_metric
  def maybe_replace_metric("price_usd", %{slug: slug}) when slug in @slugs_with_changed_price_metric, do: "price_usd_5m"

  def maybe_replace_metric("volume_usd", %{slug: slug}) when slug in @slugs_with_changed_volume_metric,
    do: "volume_usd_5m"

  def maybe_replace_metric(metric, _selector) when is_binary(metric), do: metric

  def maybe_replace_metrics([_ | _] = metrics_list, %{slug: slug} = selector) when slug in @slugs_with_changed_metric do
    Enum.map(metrics_list, &maybe_replace_metric(&1, selector))
  end

  def maybe_replace_metrics(metrics_list, _selector), do: metrics_list
end
