defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  alias Sanbase.InternalServices.TechIndicators

  def macd(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval}, _resolution) do
    TechIndicators.macd(ticker, currency, from, to, interval)
  end

  def rsi(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval, rsi_interval: rsi_interval}, _resolution) do
    TechIndicators.rsi(ticker, currency, from, to, interval, rsi_interval)
  end

  def price_volume_diff(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval}, _resolution) do
    TechIndicators.price_volume_diff(ticker, currency, from, to, interval)
  end
end
