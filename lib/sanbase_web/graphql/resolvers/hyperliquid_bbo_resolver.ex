defmodule SanbaseWeb.Graphql.Resolvers.HyperliquidBboResolver do
  alias Sanbase.Hyperliquid.Bbo.BboPrices

  def bbo_prices(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:error, error} <- BboPrices.timeseries_data(slug, from, to, interval) do
      {:error, "Cannot fetch hyperliquid BBO prices for #{slug}. Reason: #{inspect(error)}"}
    end
  end
end
