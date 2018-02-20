defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  alias Sanbase.InternalServices.TechIndicators

  def macd(
        _root,
        %{
          ticker: ticker,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          result_tail_size: result_tail_size
        },
        _resolution
      ) do
    TechIndicators.macd(ticker, currency, from, to, interval, result_tail_size)
  end

  def rsi(
        _root,
        %{
          ticker: ticker,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          rsi_interval: rsi_interval,
          result_tail_size: result_tail_size
        },
        _resolution
      ) do
    TechIndicators.rsi(ticker, currency, from, to, interval, rsi_interval, result_tail_size)
  end

  def price_volume_diff(
        _root,
        %{
          ticker: ticker,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          result_tail_size: result_tail_size
        },
        _resolution
      ) do
    TechIndicators.price_volume_diff(ticker, currency, from, to, interval, result_tail_size)
  end
end
