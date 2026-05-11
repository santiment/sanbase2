defmodule SanbaseWeb.Graphql.Resolvers.HyperliquidBboResolver do
  alias Sanbase.Hyperliquid.Bbo.BboPrices

  @doc ~s"""
  Resolver for `hyperliquidBboPrices`. Delegates to
  `Sanbase.Hyperliquid.Bbo.BboPrices.timeseries_data/4` and rewraps any error
  with a slug-tagged message.
  """
  @spec bbo_prices(any(), map(), Absinthe.Resolution.t()) ::
          {:ok, [BboPrices.point()]} | {:error, String.t()}
  def bbo_prices(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:error, error} <- BboPrices.timeseries_data(slug, from, to, interval) do
      {:error, "Cannot fetch hyperliquid BBO prices for #{slug}. Reason: #{inspect(error)}"}
    end
  end
end
