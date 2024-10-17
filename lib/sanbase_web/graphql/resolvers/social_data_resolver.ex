defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.SocialData
  alias SanbaseWeb.Graphql.SanbaseDataloader

  @context_words_default_size 10

  def get_metric_spike_explanations(
        _root,
        %{metric: metric, slug: slug, from: from, to: to},
        _resolution
      ) do
    with false <- Sanbase.Metric.hard_deprecated?(metric),
         true <- Sanbase.Metric.has_metric?(metric) do
      SocialData.Spikes.get_metric_spike_explanations(metric, %{slug: slug}, from, to)
    end
  end

  def popular_search_terms(_root, %{from: from, to: to}, _resolution) do
    Sanbase.SocialData.PopularSearchTerm.get(from, to)
  end

  def project_from_slug(_root, _args, %{source: %{slug: slug}, context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_by_slug, slug)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :project_by_slug, slug)}
    end)
  end

  def project_from_root_slug(%{slug: slug}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_by_slug, slug)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :project_by_slug, slug)}
    end)
  end

  def social_volume_projects(_root, %{}, _resolution) do
    SocialData.social_volume_projects()
  end

  def get_trending_words(
        _root,
        %{from: from, to: to, interval: interval, size: size} = args,
        resolution
      ) do
    source = Map.get(args, :source, :all)
    filter = Map.get(args, :word_type_filter, :all)

    case SocialData.TrendingWords.get_trending_words(from, to, interval, size, source, filter) do
      {:ok, result} ->
        result =
          result
          |> Enum.map(fn {datetime, top_words} ->
            %{
              datetime: datetime,
              top_words: sort_and_mask_trending_words(top_words, resolution.context.auth.plan)
            }
          end)
          |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

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
    SocialData.TrendingWords.get_word_trending_history(word, from, to, interval, size, :all)
  end

  def get_project_trending_history(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, size: size},
        _resolution
      ) do
    SocialData.TrendingWords.get_project_trending_history(slug, from, to, interval, size, :all)
  end

  def words_social_volume(
        _root,
        %{selector: %{words: _words} = selector, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    treat_as_lucene = Map.get(args, :treat_word_as_lucene_query, false)

    SocialData.social_volume(selector, from, to, interval, :total,
      treat_word_as_lucene_query: treat_as_lucene
    )
  end

  def words_social_dominance(
        _root,
        %{selector: %{words: words}} = args,
        _resolution
      ) do
    treat_as_lucene = Map.get(args, :treat_word_as_lucene_query, false)

    SocialData.SocialDominance.words_social_dominance(words,
      treat_word_as_lucene_query: treat_as_lucene
    )
  end

  def words_context(
        _root,
        %{selector: %{word: word}, source: source, size: size, from: from, to: to},
        _resolution
      ) do
    size = Enum.min([size, 30])
    SocialData.word_context([word], source, size, from, to)
  end

  def words_context(
        _root,
        %{selector: %{words: words}, source: source, size: size, from: from, to: to},
        _resolution
      ) do
    size = Enum.min([size, 30])
    SocialData.word_context(words, source, size, from, to)
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
    %{from: from, to: to} = Utils.extract_root_query_args(resolution, "get_trending_words")

    async(fn ->
      SocialData.word_context(word, :all, @context_words_default_size, from, to)
    end)
  end

  def word_trend_score(
        _root,
        %{word: word, source: source, from: from, to: to},
        _resolution
      ) do
    SocialData.word_trend_score(word, source, from, to)
  end

  def social_dominance_trending_words(_, _, _) do
    Sanbase.SocialData.SocialDominance.social_dominance_trending_words()
  end

  # private

  # FREE user doesn't see first 3 trending words
  defp sort_and_mask_trending_words(top_words, subscription_plan) do
    Enum.sort_by(top_words, & &1.score, :desc)
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      # Add a feature flag to mask first 3 words for free users
      if System.get_env("MASK_FIRST_3_WORDS_FREE_USER") in ["true", "1"] and
           subscription_plan == "FREE" and index < 3 do
        %{word | word: "***", summary: "***", bullish_summary: "***", bearish_summary: "***"}
      else
        word
      end
    end)
  end
end
