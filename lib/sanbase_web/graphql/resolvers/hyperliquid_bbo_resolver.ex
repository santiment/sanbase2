defmodule SanbaseWeb.Graphql.Resolvers.HyperliquidBboResolver do
  alias Sanbase.Hyperliquid.Bbo.BboPrices
  alias Sanbase.Project

  @source "hyperliquid"

  @doc ~s"""
  Resolver for `hyperliquidBboPrices.timeseriesData`. Delegates to
  `Sanbase.Hyperliquid.Bbo.BboPrices.timeseries_data/4` and rewraps any error
  with a slug-tagged message.
  """
  @spec timeseries_data(any(), map(), Absinthe.Resolution.t()) ::
          {:ok, [BboPrices.point()]} | {:error, String.t()}
  def timeseries_data(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:error, error} <- BboPrices.timeseries_data(slug, from, to, interval) do
      {:error, "Cannot fetch hyperliquid BBO prices for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  @doc ~s"""
  Resolver for `hyperliquidBboPrices.availableProjects`. Returns projects that
  have a `hyperliquid` source slug mapping.
  """
  @spec available_projects(any(), map(), Absinthe.Resolution.t()) :: {:ok, [%Project{}]}
  def available_projects(_root, _args, _resolution) do
    slugs =
      @source
      |> Project.SourceSlugMapping.get_source_slug_mappings()
      |> Enum.map(fn {_source_slug, project_slug} -> project_slug end)
      |> Enum.uniq()
      |> Enum.sort(:asc)

    {:ok, Project.List.by_slugs(slugs)}
  end
end
