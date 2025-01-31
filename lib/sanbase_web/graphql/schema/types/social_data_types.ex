defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  enum :most_tweet_type do
    value(:most_positive)
    value(:most_negative)
    value(:most_retweets)
    value(:most_replies)
  end

  enum :trending_word_type_filter do
    value(:project)
    value(:non_project)
    value(:all)
  end

  enum :trending_words_source do
    value(:telegram)
    value(:twitter)
    value(:reddit)
    value(:all)
  end

  enum :social_dominance_sources do
    value(:telegram)
    value(:twitter)
    value(:reddit)
    value(:all)
  end

  enum :social_volume_type do
    value(:reddit_comments_overview)
    value(:telegram_chats_overview)
    value(:telegram_discussion_overview)
  end

  input_object :selector_slug_or_slug_input_object do
    field(:slug, :string)
    field(:slugs, list_of(:string))
  end

  object :slug_tweets_object do
    field(:slug, non_null(:string))
    field(:tweets, list_of(:tweet))
  end

  object :tweet do
    field(:tweet_id, non_null(:string))
    field(:datetime, non_null(:datetime))
    field(:text, non_null(:string))
    field(:screen_name, non_null(:string))
    field(:sentiment_positive, :float)
    field(:sentiment_negative, :float)
    field(:replies_count, :integer)
    field(:retweets_count, :integer)
  end

  object :metric_spike_explanation do
    field(:spike_start_datetime, non_null(:datetime))
    field(:spike_end_datetime, non_null(:datetime))
    field(:explanation, non_null(:string))
  end

  object :metric_spike_explanations_count do
    field(:datetime, non_null(:datetime))
    field(:count, non_null(:integer))
  end

  object :metric_spike_explanations_metadata do
    field :available_metrics, non_null(list_of(:string)) do
      arg(:slug, :string, default_value: nil)
      resolve(&SocialDataResolver.get_metric_spikes_available_metrics/3)
    end

    field :available_projects, non_null(list_of(:project)) do
      arg(:metric, :string, default_value: nil)
      resolve(&SocialDataResolver.get_metric_spikes_available_projects/3)
    end

    field(:count, non_null(:integer))
  end

  object :popular_search_term do
    field(:title, non_null(:string))
    field(:options, :json)
    field(:datetime, non_null(:datetime))
    field(:search_term, non_null(:string))
    field(:selector_type, non_null(:string))
    field(:updated_at, :datetime)

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end
  end

  object :messages do
    field(:text, :string)
    field(:datetime, non_null(:datetime))
  end

  object :chart_data do
    field(:mentions_count, :float)
    field(:datetime, non_null(:datetime))
  end

  object :social_volume do
    field(:datetime, non_null(:datetime))
    field(:mentions_count, :integer)
  end

  object :social_dominance do
    field(:datetime, non_null(:datetime))
    field(:dominance, :float)
  end

  object :trending_word_summary do
    field(:source, non_null(:string))
    field(:datetime, non_null(:datetime))
    field(:summary, non_null(:string))
  end

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:word_with_context))
  end

  object :trending_word_position do
    field(:datetime, non_null(:datetime))
    field(:position, :integer)
  end

  object :word_with_context do
    field(:context, list_of(:word_context))
    field(:score, non_null(:float))
    field(:word, non_null(:string))
    field(:positive_sentiment_ratio, :float)
    field(:negative_sentiment_ratio, :float)
    field(:neutral_sentiment_ratio, :float)
    # bearish/bullish sentiment ratios
    field(:positive_bb_sentiment_ratio, :float)
    field(:negative_bb_sentiment_ratio, :float)
    field(:neutral_bb_sentiment_ratio, :float)

    field :project, :project do
      cache_resolve(&SocialDataResolver.project_from_root_slug/3)
    end

    field(:summary, non_null(:string))
    field(:bullish_summary, non_null(:string))
    field(:bearish_summary, non_null(:string))
    field(:summaries, list_of(:trending_word_summary))
  end

  object :word_trend_score do
    field(:datetime, non_null(:datetime))
    field(:score, non_null(:float))
    field(:source, :trending_words_source)
  end

  object :word_context do
    field(:word, non_null(:string))
    field(:score, non_null(:float))
  end

  object :words_context do
    field(:word, non_null(:string))
    field(:context, list_of(:word_context))
  end

  object :words_social_volume do
    field(:word, non_null(:string))
    field(:timeseries_data, list_of(:social_volume))
  end

  object :words_social_dominance do
    field(:word, non_null(:string))
    field(:social_dominance, non_null(:float))
  end

  input_object :word_selector_input_object do
    field(:word, :string)
    field(:words, list_of(:string))
  end
end
