defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  alias Sanbase.Utils.Config

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

  defp price_volume_diff_window_type(),
    do: Config.module_get(Sanbase.TechIndicators, :price_volume_diff_window_type)

  defp price_volume_diff_approximation_window() do
    Config.module_get(Sanbase.TechIndicators, :price_volume_diff_approximation_window)
    |> Sanbase.Math.to_integer()
  end

  defp price_volume_diff_comparison_window() do
    Config.module_get(Sanbase.TechIndicators, :price_volume_diff_comparison_window)
    |> Sanbase.Math.to_integer()
  end
end
