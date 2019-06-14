defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]

  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.{
    SocialData,
    TechIndicators
  }

  @context_words_default_size 10

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
          source: source,
          search_text: search_text,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    TechIndicators.topic_search(
      source,
      search_text,
      from,
      to,
      interval
    )
  end

  def trending_words(
        _root,
        %{
          source: source,
          size: size,
          hour: hour,
          from: from,
          to: to
        },
        _resolution
      ) do
    size = Enum.min([size, 100])
    SocialData.trending_words(source, size, hour, from, to)
  end

  def word_context(
        _root,
        %{
          word: word,
          source: source,
          size: size,
          from: from,
          to: to
        },
        _resolution
      ) do
    size = Enum.min([size, 100])
    SocialData.word_context(word, source, size, from, to)
  end

  def word_context(
        %{word: word},
        _args,
        resolution
      ) do
    %{
      source: source,
      from: from,
      to: to
    } = Utils.extract_root_query_args(resolution, "trending_words")

    async(fn ->
      SocialData.word_context(word, source, @context_words_default_size, from, to)
    end)
  end

  def word_trend_score(
        _root,
        %{
          word: word,
          source: source,
          from: from,
          to: to
        },
        _resolution
      ) do
    SocialData.word_trend_score(word, source, from, to)
  end

  def top_social_gainers_losers(_root, args, _resolution) do
    SocialData.top_social_gainers_losers(args)
  end

  def social_gainers_losers_status(_root, args, _resolution) do
    SocialData.social_gainers_losers_status(args)
  end

  def social_dominance(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          source: source
        },
        _resolution
      ) do
    SocialData.social_dominance(
      slug,
      from,
      to,
      interval,
      source
    )
  end

  def news(
        _root,
        %{
          tag: tag,
          from: from,
          to: to,
          size: size
        },
        _resolution
      ) do
    SocialData.google_news(
      tag,
      from,
      to,
      size
    )
  end
end
