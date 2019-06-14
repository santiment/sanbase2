defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.TechIndicators
  alias Sanbase.Model.Project

  def price_volume_diff(
        _root,
        %{
          slug: slug,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          size: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.PriceVolumeDifference.price_volume_diff(
      Project.by_slug(slug),
      currency,
      from,
      to,
      interval,
      price_volume_diff_window_type(),
      price_volume_diff_approximation_window(),
      price_volume_diff_comparison_window(),
      result_size_tail
    )
  end

  def metric_anomaly(
        _root,
        %{
          metric: metric,
          slug: slug,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    TechIndicators.metric_anomaly(
      metric,
      slug,
      from,
      to,
      interval
    )
  end

  defp price_volume_diff_window_type(),
    do: Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :window_type)

  defp price_volume_diff_approximation_window() do
    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :approximation_window)
      |> Integer.parse()

    res
  end

  defp price_volume_diff_comparison_window() do
    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :comparison_window)
      |> Integer.parse()

    res
  end
end
