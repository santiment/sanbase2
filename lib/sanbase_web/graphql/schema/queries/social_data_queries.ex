defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.{
    TimeframeRestriction,
    ApikeyAuth,
    MultipleAuth,
    JWTAuth
  }

  alias SanbaseWeb.Graphql.Resolvers.{
    SocialDataResolver,
    TwitterResolver,
    ElasticsearchResolver
  }

  alias SanbaseWeb.Graphql.Complexity

  import_types(SanbaseWeb.Graphql.SocialDataTypes)
  import_types(SanbaseWeb.Graphql.ElasticsearchTypes)

  object :social_data_queries do
    @desc "Fetch the current data for a Twitter account (currently includes only Twitter followers)."
    field :twitter_data, :twitter_data do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:slug, :string)

      cache_resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Fetch historical data for a Twitter account (currently includes only Twitter followers)."
    field :history_twitter_data, list_of(:twitter_data) do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&TwitterResolver.history_twitter_data/3)
    end

    @desc ~s"""
    Returns lists with trending words and their corresponding trend score.

    Arguments description:
      * source - one of the following:
        1. TELEGRAM
        2. PROFESSIONAL_TRADERS_CHAT
        3. REDDIT
        4. ALL
      * size - an integer showing how many words should be included in the top list (max 100)
      * hour - an integer from 0 to 23 showing the hour of the day when the calculation was executed
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :trending_words, list_of(:trending_words) do
      arg(:source, non_null(:trending_words_sources))
      arg(:size, non_null(:integer))
      arg(:hour, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.trending_words/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns the historical score for a given word within a time interval

    Arguments description:
      * word - the word the historical score is requested for
      * source - one of the following:
        1. TELEGRAM
        2. PROFESSIONAL_TRADERS_CHAT
        3. REDDIT
        4. ALL
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :word_trend_score, list_of(:word_trend_score) do
      arg(:word, non_null(:string))
      arg(:source, non_null(:trending_words_sources))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.word_trend_score/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns context for a trending word and the corresponding context score.

    Arguments description:
      * word - the word the context is requested for
      * source - one of the following:
        1. TELEGRAM
        2. PROFESSIONAL_TRADERS_CHAT
        3. REDDIT
        4. ALL
      * size - an integer showing how many words should be included in the top list (max 100)
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :word_context, list_of(:word_context) do
      arg(:word, non_null(:string))
      arg(:source, non_null(:trending_words_sources))
      arg(:size, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.word_context/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc "Fetch the Twitter mention count for a given ticker and time period."
    field :twitter_mention_count, list_of(:twitter_mention_count) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.twitter_mention_count/3)
    end

    @desc ~s"""
    Fetch the emoji sentiment for a given ticker and time period.
    This metric is a basic sentiment analysis, based on emojis used in social media.
    """
    field :emojis_sentiment, list_of(:emojis_sentiment) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      middleware(MultipleAuth, [{JWTAuth, san_tokens: 1000}, {ApikeyAuth, san_tokens: 1000}])
      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&SocialDataResolver.emojis_sentiment/3)
    end

    @desc ~s"""
    Returns a list of mentions count for a given project and time interval.

    Arguments description:
      * slug - a string uniquely identifying a project
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * socialVolumeType - the source of mention counts, one of the following:
        1. "PROFESSIONAL_TRADERS_CHAT_OVERVIEW" - shows how many times the given project has been mentioned in the professional traders chat
        2. "TELEGRAM_CHATS_OVERVIEW" - shows how many times the given project has been mentioned across all telegram chats, except the project's own community chat (if there is one)
        3. "TELEGRAM_DISCUSSION_OVERVIEW" - the general volume of messages in the project's community chat (if there is one)
        4. "DISCORD_DISCUSSION_OVERVIEW" - shows how many times the given project has been mentioned in the discord channels
    """
    field :social_volume, list_of(:social_volume) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")
      arg(:social_volume_type, non_null(:social_volume_type))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      resolve(&SocialDataResolver.social_volume/3)
    end

    @desc ~s"""
    Returns a list of slugs for which there is social volume data.
    """
    field :social_volume_projects, list_of(:string) do
      cache_resolve(&SocialDataResolver.social_volume_projects/3)
    end

    @desc ~s"""
    Returns lists with the mentions of the search phrase from the selected source. The results are in two formats - the messages themselves and the data for building graph representation of the result.

    Arguments description:
      * source - one of the following:
        1. TELEGRAM
        2. PROFESSIONAL_TRADERS_CHAT
        3. REDDIT
        4. DISCORD
      * searchText - a string containing the key words for which the sources should be searched.
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :topic_search, :topic_search do
      arg(:source, non_null(:topic_search_sources))
      arg(:search_text, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime)
      arg(:interval, non_null(:string), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      cache_resolve(&SocialDataResolver.topic_search/3, ttl: 600, max_ttl_offset: 240)
    end

    @desc ~s"""
    Returns the % of the social dominance a given project has over time in a given social channel.

    Arguments description:
      * slug - a string uniquely identifying a project
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * source - the source of mention counts, one of the following:
        1. PROFESSIONAL_TRADERS_CHAT - shows the relative social dominance of this project on the web chats where trades talk
        2. TELEGRAM - shows the relative social dominance of this project in the telegram crypto channels
        3. DISCORD - shows the relative social dominance of this project on discord crypto communities
        4. REDDIT - shows the relative social dominance of this project on crypto subreddits
        5. ALL - shows the average value of the social dominance across all sources
    """
    field :social_dominance, list_of(:social_dominance) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")
      arg(:source, non_null(:social_dominance_sources), default_value: :all)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      resolve(&SocialDataResolver.social_dominance/3)
    end

    @desc ~s"""
    Returns the news for given word.

    Arguments description:
      * tag - Project name, ticker or other crypto related words.
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * size - size limit of the returned results
    """
    field :news, list_of(:news) do
      arg(:tag, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:size, :integer, default_value: 10)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)

      resolve(&SocialDataResolver.news/3)
    end

    @desc "Returns statistics for the data stored in elasticsearch"
    field :elasticsearch_stats, :elasticsearch_stats do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&ElasticsearchResolver.stats/3)
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
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:status, non_null(:social_gainers_losers_status_enum))
      arg(:size, :integer, default_value: 10)
      arg(:time_window, non_null(:string))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
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
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:time_window, non_null(:string))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      cache_resolve(&SocialDataResolver.social_gainers_losers_status/3)
    end
  end
end
