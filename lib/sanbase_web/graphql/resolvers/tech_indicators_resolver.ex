defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  alias Sanbase.InternalServices.TechIndicators
  alias Sanbase.Utils.Config

  require Sanbase.Utils.Config

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
      price_volume_diff_ma_window_type(),
      price_volume_diff_ma_approximation_window(),
      price_volume_diff_ma_comparison_window(),
      result_size_tail
    )
  end

  def twitter_mention_count(
        _root,
        %{
          ticker: ticker,
          from: from,
          to: to,
          interval: interval,
          result_size_tail: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.twitter_mention_count(
      ticker,
      from,
      to,
      interval,
      result_size_tail
    )
  end

  def emojis_sentiment(
        _root,
        %{
          from: from,
          to: to,
          interval: interval,
          result_size_tail: result_size_tail
        },
        _resolution
      ) do
    TechIndicators.emojis_sentiment(
      from,
      to,
      interval,
      result_size_tail
    )
  end

  defp price_volume_diff_ma_window_type() do
    Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :window_type)
  end

  defp price_volume_diff_ma_approximation_window() do
    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :approximation_window)
      |> Integer.parse()

    res
  end

  defp price_volume_diff_ma_comparison_window() do
    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :comparison_window)
      |> Integer.parse()

    res
  end
end
