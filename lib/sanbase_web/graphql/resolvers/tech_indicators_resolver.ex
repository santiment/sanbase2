defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.InternalServices.TechIndicators

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

  def erc20_exchange_funds_flow(
        _root,
        %{
          from: from,
          to: to
        },
        _resolution
      ) do
    TechIndicators.erc20_exchange_funds_flow(
      from,
      to
    )
  end

  def social_volume(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          social_volume_type: social_volume_type
        },
        _resolution
      ) do
    TechIndicators.social_volume(
      slug,
      from,
      to,
      interval,
      social_volume_type
    )
  end

  def social_volume_projects(
        _root,
        %{},
        _resolution
      ) do
    TechIndicators.social_volume_projects()
  end

  def topic_search(
        _root,
        %{
          sources: sources,
          search_text: search_text,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    TechIndicators.topic_search(
      sources,
      search_text,
      from,
      to,
      interval
    )
  end

  def topic_search_overview(
        _root,
        %{
          source: source,
          search_text: search_text,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    TechIndicators.topic_search_overview(
      source,
      search_text,
      from,
      to,
      interval
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
