defmodule Sanbase.Metric.MetricReplace do
  @slugs_with_changed_metric ["gold", "s-and-p-500", "crude-oil", "dxy"]

  def maybe_replace_metric("price_usd", %{slug: slug}) when slug in @slugs_with_changed_metric,
    do: "price_usd_5m"

  def maybe_replace_metric(metric, _selector) when is_binary(metric), do: metric

  def maybe_replace_metrics(metrics_list, %{slug: slug} = selector)
      when slug in @slugs_with_changed_metric and is_list(metrics_list) do
    Enum.map(metrics_list, &maybe_replace_metric(&1, selector))
  end

  def maybe_replace_metrics(metrics_list, _selector), do: metrics_list
end
