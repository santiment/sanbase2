defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.{
    TimeframeRestriction,
    ApikeyAuth,
    MultipleAuth,
    JWTAuth
  }

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver

  alias SanbaseWeb.Graphql.Complexity

  import_types(SanbaseWeb.Graphql.SocialDataTypes)

  object :social_data_queries do
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
  end
end
