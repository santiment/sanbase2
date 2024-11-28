defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver

  object :social_data_queries do
    field :get_most_tweets, list_of(:slug_tweets_object) do
      meta(access: :free)

      arg(:selector, non_null(:selector_slug_or_slug_input_object))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:size, non_null(:integer))
      arg(:tweet_type, non_null(:most_tweet_type))

      cache_resolve(&SocialDataResolver.get_most_tweets/3)
    end

    field :get_metric_spike_explanations, list_of(:metric_spike_explanation) do
      meta(access: :free)

      arg(:metric, non_null(:string))
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&SocialDataResolver.get_metric_spike_explanations/3)
    end

    field :popular_search_terms, list_of(:popular_search_term) do
      meta(access: :free)

      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&SocialDataResolver.popular_search_terms/3)
    end

    @desc ~s"""
    Returns lists with trending words and their corresponding trend score.

    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * interval - a string representing at what interval the words are returned
    * size - an integer showing how many words should be included in the top list (max 30)
    """
    field :get_trending_words, list_of(:trending_words) do
      meta(access: :restricted)

      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:size, non_null(:integer))
      arg(:word_type_filter, :trending_word_type_filter)

      arg(:source, :trending_words_source)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.get_trending_words/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns lists with the position of a word in the list of trending words
    over time

    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * interval - a string representing at what interval the words are returned
    * size - an integer showing how many top words should be considered in the check
    """
    field :get_word_trending_history, list_of(:trending_word_position) do
      meta(access: :restricted)

      arg(:word, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:size, non_null(:integer))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})

      cache_resolve(&SocialDataResolver.get_word_trending_history/3,
        ttl: 300,
        max_ttl_offset: 240
      )
    end

    @desc ~s"""
    Returns lists with the position of a word in the list of trending words
    over time

    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * interval - a string representing at what interval the words are returned
    * size - an integer showing how many top words should be considered in the check
    """
    field :get_project_trending_history, list_of(:trending_word_position) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:size, non_null(:integer))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})

      cache_resolve(&SocialDataResolver.get_project_trending_history/3,
        ttl: 300,
        max_ttl_offset: 120
      )
    end

    @desc ~s"""
    Returns the historical score for a given word within a time interval

    Arguments description:
      * word - the word the historical score is requested for
      * source - one of the following:
        1. TELEGRAM
        2. REDDIT
        3. TWITTER_CRYPTO
        4. ALL
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :word_trend_score, list_of(:word_trend_score) do
      meta(access: :restricted)

      arg(:word, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:source, :trending_words_source)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.word_trend_score/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns context for a trending word and the corresponding context score.

    Arguments description:
      * word - the word the context is requested for
      * source - one of the following:
        1. TELEGRAM
        2. REDDIT
        3. ALL
      * size - an integer showing how many words should be included in the top list (max 100)
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :word_context, list_of(:word_context) do
      meta(access: :restricted)

      arg(:word, :string)
      arg(:source, non_null(:trending_words_source))
      arg(:size, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.word_context/3, ttl: 600, max_ttl_offset: 240)
    end

    field :words_context, list_of(:words_context) do
      meta(access: :restricted)

      arg(:selector, :word_selector_input_object)
      arg(:source, non_null(:trending_words_source))
      arg(:size, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.words_context/3, ttl: 600, max_ttl_offset: 240)
    end

    field :words_social_volume, list_of(:words_social_volume) do
      meta(access: :restricted)

      arg(:selector, :word_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      @desc ~s"""
      If true, the word will be treated as a Lucene query. Default is false.
      Lucene queries allows the word to be not a single word, but a query like: eth AND nft.
      If false, the words are all lowercased and the AND/NOT/OR keywords meaning is lost.
      """
      arg(:treat_word_as_lucene_query, :boolean, default_value: false)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.words_social_volume/3, ttl: 600, max_ttl_offset: 240)
    end

    field :words_social_dominance, list_of(:words_social_dominance) do
      meta(access: :free)

      arg(:selector, :word_selector_input_object)

      @desc ~s"""
      If true, the word will be treated as a Lucene query. Default is false.
      Lucene queries allows the word to be not a single word, but a query like: eth AND nft.
      If false, the words are all lowercased and the AND/NOT/OR keywords meaning is lost.
      """
      arg(:treat_word_as_lucene_query, :boolean, default_value: false)

      cache_resolve(&SocialDataResolver.words_social_dominance/3, ttl: 600, max_ttl_offset: 240)
    end

    field :words_social_dominance_old, list_of(:words_social_dominance) do
      meta(access: :free)

      arg(:selector, :word_selector_input_object)

      @desc ~s"""
      If true, the word will be treated as a Lucene query. Default is false.
      Lucene queries allows the word to be not a single word, but a query like: eth AND nft.
      If false, the words are all lowercased and the AND/NOT/OR keywords meaning is lost.
      """
      arg(:treat_word_as_lucene_query, :boolean, default_value: false)

      cache_resolve(&SocialDataResolver.words_social_dominance/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns a list of slugs for which there is social volume data.
    """
    field :social_volume_projects, list_of(:string) do
      meta(access: :free)

      cache_resolve(&SocialDataResolver.social_volume_projects/3)
    end

    field :social_dominance_trending_words, :float do
      meta(access: :free)

      cache_resolve(&SocialDataResolver.social_dominance_trending_words/3)
    end
  end
end
