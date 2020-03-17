defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.{SocialData, TechIndicators}
  alias SanbaseWeb.Graphql.SanbaseDataloader

  @context_words_default_size 10

  def project_from_slug(_root, _args, %{source: %{slug: slug}, context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_by_slug, slug)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :project_by_slug, slug)}
    end)
  end

  def twitter_mention_count(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval, result_size_tail: size},
        _resolution
      ) do
    TechIndicators.twitter_mention_count(ticker, from, to, interval, size)
  end

  def emojis_sentiment(
        _root,
        %{from: from, to: to, interval: interval, result_size_tail: size},
        _resolution
      ) do
    TechIndicators.emojis_sentiment(from, to, interval, size)
  end

  def social_volume(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, social_volume_type: type},
        _resolution
      ) do
    # The `*_discussion_overview` are counting the total number of messages in a given medium
    # Deprecated. To be replaced with `getMetric(metric: "community_messages_count_*")` and
    # `getMetric(metric: "social_volume_*")`
    case type in [:telegram_discussion_overview, :discord_discussion_overview] do
      true ->
        SocialData.community_messages_count(slug, from, to, interval, type)

      false ->
        SocialData.social_volume(slug, from, to, interval, type)
    end
  end

  def social_volume_projects(_root, %{}, _resolution) do
    SocialData.social_volume_projects()
  end

  def topic_search(
        _root,
        %{source: source, search_text: search_text, from: from, to: to, interval: interval},
        _resolution
      ) do
    case SocialData.topic_search(search_text, from, to, interval, source) do
      {:ok, data} -> {:ok, %{chart_data: data}}
      {:error, error} -> {:error, error}
    end
  end

  def get_trending_words(
        _root,
        %{from: from, to: to, interval: interval, size: size},
        _resolution
      ) do
    case SocialData.TrendingWords.get_trending_words(from, to, interval, size) do
      {:ok, result} ->
        result =
          result
          |> Enum.map(fn {datetime, top_words} -> %{datetime: datetime, top_words: top_words} end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_word_trending_history(
        _root,
        %{word: word, from: from, to: to, interval: interval, size: size},
        _resolution
      ) do
    SocialData.TrendingWords.get_word_trending_history(word, from, to, interval, size)
  end

  def get_project_trending_history(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, size: size},
        _resolution
      ) do
    SocialData.TrendingWords.get_project_trending_history(slug, from, to, interval, size)
  end

  def trending_words(
        _root,
        %{source: source, size: size, hour: hour, from: from, to: to},
        _resolution
      ) do
    size = Enum.min([size, 30])
    SocialData.trending_words(source, size, hour, from, to)
  end

  def word_context(
        _root,
        %{word: word, source: source, size: size, from: from, to: to},
        _resolution
      ) do
    size = Enum.min([size, 30])
    SocialData.word_context(word, source, size, from, to)
  end

  def word_context(%{word: word}, _args, resolution) do
    %{source: source, from: from, to: to} =
      Utils.extract_root_query_args(resolution, "trending_words")

    async(fn ->
      SocialData.word_context(word, source, @context_words_default_size, from, to)
    end)
  end

  def word_trend_score(
        _root,
        %{word: word, source: source, from: from, to: to},
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
        %{slug: slug, from: from, to: to, interval: interval, source: source},
        _resolution
      ) do
    SocialData.social_dominance(%{slug: slug}, from, to, interval, source)
  end

  def news(_root, %{tag: tag, from: from, to: to, size: size}, _resolution) do
    SocialData.google_news(tag, from, to, size)
  end
end
