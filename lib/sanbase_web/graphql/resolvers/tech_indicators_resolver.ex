defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  alias Sanbase.InternalServices.TechIndicators

  @price_volume_diff_ma_approximation_window 14
  @price_volume_diff_ma_comparison_window 7

  def macd(
        _root,
        %{
          ticker: ticker,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          result_size_tail: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.macd(ticker, currency, from, to, interval, result_size_tail)
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
          result_size_tail: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.rsi(ticker, currency, from, to, interval, rsi_interval, result_size_tail)
  end

  def price_volume_diff(
        _root,
        %{
          ticker: ticker,
          currency: currency,
          from: from,
          to: to,
          interval: interval,
          result_size_tail: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.price_volume_diff_ma(
      ticker,
      currency,
      from,
      to,
      interval,
      @price_volume_diff_ma_approximation_window,
      @price_volume_diff_ma_comparison_window,
      result_size_tail
    )
  end
end
