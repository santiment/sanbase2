defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.SocialData
  alias SanbaseWeb.Graphql.SanbaseDataloader

  @context_words_default_size 10

  def get_most_tweets(
        _root,
        %{selector: selector, from: from, to: to, size: size, tweet_type: type},
        _resolution
      ) do
    SocialData.Tweet.get_most_tweets(selector, type, from, to, size)
  end

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

  def get_metric_spike_explanations_count(
        _root,
        %{metric: metric, slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with false <- Sanbase.Metric.hard_deprecated?(metric),
         true <- Sanbase.Metric.has_metric?(metric) do
      SocialData.Spikes.get_metric_spike_explanations_count(
        metric,
        %{slug: slug},
        from,
        to,
        interval
      )
    end
  end

  def get_metric_spike_explanations_metadata(_root, _args, _resolution) do
    {:ok, %{}}
  end

  def get_metric_spikes_available_projects(_root, %{metric: metric}, _resolution)
      when is_binary(metric) do
    with false <- Sanbase.Metric.hard_deprecated?(metric),
         true <- Sanbase.Metric.has_metric?(metric),
         {:ok, slugs} <- SocialData.Spikes.available_assets() do
      slugs = Enum.sort(slugs, :asc)
      {:ok, Sanbase.Project.List.by_slugs(slugs)}
    end
  end

  def get_metric_spikes_available_projects(_root, _args, _resolution) do
    with {:ok, slugs} <- SocialData.Spikes.available_assets() do
      slugs = Enum.sort(slugs, :asc)
      {:ok, Sanbase.Project.List.by_slugs(slugs)}
    end
  end

  def get_metric_spikes_available_metrics(_root, args, _resolution) do
    if slug = Map.get(args, :slug) do
      SocialData.Spikes.available_metrics(%{slug: slug})
    else
      SocialData.Spikes.available_metrics()
    end
  end

  def popular_search_terms(_root, %{from: from, to: to}, _resolution) do
    Sanbase.SocialData.PopularSearchTerm.get(from, to)
  end

  def top_documents(
        %{top_documents_ids: ["***"]},
        _args,
        _resolution
      ) do
    # If the word is a masked one, we don't fetch the real documents but hide them
    {:ok,
     [%{text: "***", screen_name: "***", source: "***", document_id: "***", document_url: nil}]}
  end

  def top_documents(
        %{top_documents_ids: doc_ids},
        _args,
        %{context: %{loader: loader}}
      ) do
    loader
    |> Dataloader.load(SanbaseDataloader, :social_documents_by_ids, doc_ids)
    |> on_load(fn loader ->
      result = Dataloader.get_many(loader, SanbaseDataloader, :social_documents_by_ids, doc_ids)

      {:ok, result}
    end)
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

  def get_trending_stories(
        _root,
        %{from: from, to: to, interval: interval, size: size} = args,
        resolution
      ) do
    source = Map.get(args, :source)

    case SocialData.TrendingStories.get_trending_stories(from, to, interval, size, source) do
      {:ok, result} ->
        result =
          result
          |> Enum.map(fn {datetime, top_stories} ->
            %{
              datetime: datetime,
              top_stories:
                sort_and_mask_trending_stories(top_stories, resolution.context.auth.plan)
            }
          end)
          |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
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
    is_market_metric = Map.get(args, :is_market_metric, false)

    SocialData.social_volume(selector, from, to, interval, :total,
      treat_word_as_lucene_query: treat_as_lucene,
      is_market_metric: is_market_metric
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

  def social_dominance_trending_words(_, _, _) do
    Sanbase.SocialData.SocialDominance.social_dominance_trending_words()
  end

  # private

  # FREE user doesn't see first 3 trending words
  defp sort_and_mask_trending_words(top_words, subscription_plan) do
    Enum.sort_by(top_words, & &1.score, :desc)
    |> Enum.with_index()
    |> Enum.map(fn {word, word_index} ->
      # Add a feature flag to mask first 3 words for free users
      if should_mask?(word_index, subscription_plan) do
        %{
          word
          | word: "***",
            summary: "***",
            bullish_summary: "***",
            bearish_summary: "***",
            top_documents_ids: if(word.top_documents_ids == [], do: [], else: ["***"])
        }
      else
        word
      end
    end)
  end

  defp sort_and_mask_trending_stories(top_stories, subscription_plan) do
    Enum.sort_by(top_stories, & &1.score, :desc)
    |> Enum.with_index()
    |> Enum.map(fn {story, story_index} ->
      # Add a feature flag to mask first 3 words for free users
      if should_mask?(story_index, subscription_plan) do
        %{
          story
          | title: "***",
            summary: "***",
            search_text: "***",
            related_tokens: ["***"]
        }
      else
        story
      end
    end)
  end

  defp should_mask?(word_index, subscription_plan) do
    # Free users should not see the data for the first 3 trending words
    word_index < 3 and
      System.get_env("MASK_FIRST_3_WORDS_FREE_USER") in ["true", "1"] and
      subscription_plan == "FREE"
  end
end
