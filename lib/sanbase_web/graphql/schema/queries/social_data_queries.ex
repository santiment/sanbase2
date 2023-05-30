defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  alias SanbaseWeb.Graphql.Resolvers.{
    SocialDataResolver,
    TwitterResolver
  }

  alias SanbaseWeb.Graphql.Complexity

  object :social_data_queries do
    field :popular_search_terms, list_of(:popular_search_term) do
      meta(access: :free)

      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&SocialDataResolver.popular_search_terms/3)
    end

    @desc "Fetch the current data for a Twitter account (currently includes only Twitter followers)."
    field :twitter_data, :twitter_data do
      meta(access: :free)

      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:slug, :string)

      cache_resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Fetch historical data for a Twitter account (currently includes only Twitter followers)."
    field :history_twitter_data, list_of(:twitter_data) do
      meta(access: :free)

      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&TwitterResolver.history_twitter_data/3)
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

      arg(:sources, list_of(:trending_words_sources))

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
        3. ALL
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :word_trend_score, list_of(:word_trend_score) do
      meta(access: :restricted)

      arg(:word, non_null(:string))
      arg(:source, non_null(:trending_words_sources))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

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
      arg(:source, non_null(:trending_words_sources))
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
      arg(:source, non_null(:trending_words_sources))
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

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.words_social_volume/3, ttl: 600, max_ttl_offset: 240)
    end

    field :words_social_dominance, list_of(:words_social_dominance) do
      meta(access: :free)

      arg(:selector, :word_selector_input_object)

      cache_resolve(&SocialDataResolver.words_social_dominance/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns a list of mentions count for a given project and time interval.

    Arguments description:
      * slug - a string uniquely identifying a project
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * socialVolumeType - the source of mention counts, one of the following:
        1. "TELEGRAM_CHATS_OVERVIEW" - shows how many times the given project has been mentioned across all telegram chats, except the project's own community chat (if there is one)
        2. "TELEGRAM_DISCUSSION_OVERVIEW" - the general volume of messages in the project's community chat (if there is one)
    """
    field :social_volume, list_of(:social_volume) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval), default_value: "1d")
      arg(:social_volume_type, non_null(:social_volume_type))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.social_volume/3)
    end

    @desc ~s"""
    Returns a list of slugs for which there is social volume data.
    """
    field :social_volume_projects, list_of(:string) do
      meta(access: :free)

      cache_resolve(&SocialDataResolver.social_volume_projects/3)
    end

    @desc ~s"""
    Returns lists with the mentions of the search phrase from the selected source. The results are in two formats - the messages themselves and the data for building graph representation of the result.

    Arguments description:
      * source - one of the following:
        1. TELEGRAM
        2. REDDIT
      * searchText - a string containing the key words for which the sources should be searched.
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :topic_search, :topic_search do
      meta(access: :restricted)

      arg(:source, non_null(:topic_search_sources))
      arg(:search_text, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime)
      arg(:interval, non_null(:interval), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.topic_search/3)
    end

    @desc ~s"""
    Returns the % of the social dominance a given project has over time in a given social channel.

    Arguments description:
      * slug - a string uniquely identifying a project
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * source - the source of mention counts, one of the following:
        1. TELEGRAM - shows the relative social dominance of this project in the telegram crypto channels
        2. REDDIT - shows the relative social dominance of this project on crypto subreddits
        3. ALL - shows the average value of the social dominance across all sources
    """
    field :social_dominance, list_of(:social_dominance) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval), default_value: "1d")
      arg(:source, non_null(:social_dominance_sources), default_value: :all)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&SocialDataResolver.social_dominance/3)
    end

    @desc """
    Top social gainers/losers returns the social volume changes of all crypto projects.

    * `from` - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * `to` - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * `status` can be one of: `ALL`, `GAINER`, `LOSER`, `NEWCOMER`
    * `size` - count of returned projects for status
    * `time_window` - the `change` time window in days. Should be between `2d` and `30d`.
    """
    field :top_social_gainers_losers, list_of(:top_social_gainers_losers) do
      meta(access: :restricted)

      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:status, non_null(:social_gainers_losers_status_enum))
      arg(:size, :integer, default_value: 10)
      arg(:time_window, non_null(:string))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.top_social_gainers_losers/3)
    end

    @desc """
    Returns the social gainers/losers `status` and `change` for given slug.
    Returned `status` can be one of: `GAINER`, `LOSER`, `NEWCOMER.`

    * `slug` - a string uniquely identifying a project
    * `from` - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * `to` - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * `time_window` - the `change` time window in days. Should be between `2d` and `30d`.
    """
    field :social_gainers_losers_status, list_of(:social_gainers_losers_status) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:time_window, non_null(:string))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.social_gainers_losers_status/3)
    end

    field :social_dominance_trending_words, :float do
      meta(access: :free)

      cache_resolve(&SocialDataResolver.social_dominance_trending_words/3)
    end
  end
end
