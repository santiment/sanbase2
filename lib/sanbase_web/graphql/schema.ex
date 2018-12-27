defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql.Resolvers.{
    AccountResolver,
    PriceResolver,
    ProjectResolver,
    ProjectTransactionsResolver,
    GithubResolver,
    TwitterResolver,
    EtherbiResolver,
    VotingResolver,
    TechIndicatorsResolver,
    SocialDataResolver,
    FileResolver,
    PostResolver,
    MarketSegmentResolver,
    ApikeyResolver,
    UserListResolver,
    ElasticsearchResolver,
    ClickhouseResolver,
    ExchangeResolver
  }

  import SanbaseWeb.Graphql.Helpers.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Complexity.TechIndicatorsComplexity

  alias SanbaseWeb.Graphql.Middlewares.{
    MultipleAuth,
    BasicAuth,
    JWTAuth,
    ApikeyAuth,
    ProjectPermissions,
    PostPermissions,
    ApiTimeframeRestriction,
    ApiUsage
  }

  import_types(Absinthe.Plug.Types)
  import_types(Absinthe.Type.Custom)
  import_types(SanbaseWeb.Graphql.CustomTypes)
  import_types(SanbaseWeb.Graphql.AccountTypes)
  import_types(SanbaseWeb.Graphql.PriceTypes)
  import_types(SanbaseWeb.Graphql.ProjectTypes)
  import_types(SanbaseWeb.Graphql.GithubTypes)
  import_types(SanbaseWeb.Graphql.TwitterTypes)
  import_types(SanbaseWeb.Graphql.EtherbiTypes)
  import_types(SanbaseWeb.Graphql.VotingTypes)
  import_types(SanbaseWeb.Graphql.TechIndicatorsTypes)
  import_types(SanbaseWeb.Graphql.SocialDataTypes)
  import_types(SanbaseWeb.Graphql.TransactionTypes)
  import_types(SanbaseWeb.Graphql.FileTypes)
  import_types(SanbaseWeb.Graphql.UserListTypes)
  import_types(SanbaseWeb.Graphql.MarketSegmentTypes)
  import_types(SanbaseWeb.Graphql.ElasticsearchTypes)
  import_types(SanbaseWeb.Graphql.ClickhouseTypes)
  import_types(SanbaseWeb.Graphql.ExchangeTypes)

  def dataloader() do
    alias SanbaseWeb.Graphql.SanbaseRepo
    alias SanbaseWeb.Graphql.PriceStore

    Dataloader.new()
    |> Dataloader.add_source(SanbaseRepo, SanbaseRepo.data())
    |> Dataloader.add_source(PriceStore, PriceStore.data())
  end

  def context(ctx) do
    Map.put(ctx, :loader, dataloader())
  end

  def plugins do
    [
      Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()
    ]
  end

  def middleware(middlewares, field, object) do
    prometeheus_middlewares =
      SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter.instrument(middlewares, field, object)
      |> SanbaseWeb.Graphql.Prometheus.CounterInstrumenter.instrument(field, object)

    case object.identifier do
      :query ->
        [ApiUsage | prometeheus_middlewares]

      _ ->
        prometeheus_middlewares
    end
  end

  query do
    @desc "Returns the user currently logged in."
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    @desc "Fetch all market segments."
    field :all_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.all_market_segments/3)
    end

    @desc "Fetch ERC20 projects' market segments."
    field :erc20_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.erc20_market_segments/3)
    end

    @desc "Fetch currency projects' market segments."
    field :currencies_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.currencies_market_segments/3)
    end

    @desc "Fetch all projects that have price data."
    field :all_projects, list_of(:project) do
      middleware(ProjectPermissions)
      cache_resolve(&ProjectResolver.all_projects/3)
    end

    @desc "Fetch all ERC20 projects."
    field :all_erc20_projects, list_of(:project) do
      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_erc20_projects/3)
    end

    @desc "Fetch all currency projects. A currency project is a project that has price data but is not classified as ERC20."
    field :all_currency_projects, list_of(:project) do
      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_currency_projects/3)
    end

    @desc "Fetch all project transparency projects. This query requires basic authentication."
    field :all_projects_project_transparency, list_of(:project) do
      middleware(BasicAuth)
      resolve(&ProjectResolver.all_projects(&1, &2, &3, true))
    end

    @desc "Fetch a project by its ID."
    field :project, :project do
      arg(:id, non_null(:id))
      # this is to filter the wallets
      arg(:only_project_transparency, :boolean, default_value: false)

      middleware(ProjectPermissions)
      resolve(&ProjectResolver.project/3)
    end

    @desc "Fetch a project by a unique identifier."
    field :project_by_slug, :project do
      arg(:slug, non_null(:string))
      arg(:only_project_transparency, :boolean, default_value: false)

      middleware(ProjectPermissions)
      cache_resolve(&ProjectResolver.project_by_slug/3)
    end

    @desc "Fetch all projects that have ETH contract information."
    field :all_projects_with_eth_contract_info, list_of(:project) do
      middleware(BasicAuth)

      cache_resolve(&ProjectResolver.all_projects_with_eth_contract_info/3)
    end

    @desc "Fetch price history for a given slug and time interval."
    field :history_price, list_of(:price_point) do
      arg(:slug, :string)
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "")

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&PriceResolver.history_price/3)
    end

    @desc ~s"""
    Fetch open, high, low close price values for a given slug and every time interval between from-to.
    """

    field :ohlc, list_of(:ohlc) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime)
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&PriceResolver.ohlc/3)
    end

    @desc ~s"""
    Fetch data for each of the projects in the slugs lists
    """
    field :projects_list_stats, list_of(:project_stats) do
      arg(:slugs, non_null(list_of(:string)))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&PriceResolver.multiple_projects_stats/3)
    end

    @desc ~s"""
    Fetch data bucketed by interval. The returned marketcap and volume are the sum
    of the marketcaps and volumes of all projects for that given time interval
    """
    field :projects_list_history_stats, list_of(:combined_projects_stats) do
      arg(:slugs, non_null(list_of(:string)))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")

      cache_resolve(&ProjectResolver.combined_history_stats/3)
    end

    @desc "Returns a list of available github repositories."
    field :github_availables_repos, list_of(:string) do
      cache_resolve(&GithubResolver.available_repos/3)
    end

    @desc ~s"""
    Returns a list of github activity for a given slug and time interval.

    Arguments description:
      * interval - an integer followed by one of: `s`, `m`, `h`, `d` or `w`
      * transform - one of the following:
        1. None (default)
        2. movingAverage
      * movingAverageIntervalBase - used only if transform is `movingAverage`.
        An integer followed by one of: `s`, `m`, `h`, `d` or `w`, representing time units.
        It is used to calculate the moving avarage interval.
    """
    field :github_activity, list_of(:activity_point) do
      arg(:slug, :string)
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "")
      arg(:transform, :string, default_value: "None")
      arg(:moving_average_interval_base, :string, default_value: "1w")

      middleware(ApiTimeframeRestriction, %{allow_historical_data: true})

      cache_resolve(&GithubResolver.activity/3)
    end

    @desc ~s"""
    Gets the pure dev activity of a project. Pure dev activity is the number of all events
    excluding Comments, Issues and PR Comments
    """
    field :dev_activity, list_of(:activity_point) do
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string))
      arg(:transform, :string, default_value: "None")
      arg(:moving_average_interval_base, :integer, default_value: 7)

      middleware(ApiTimeframeRestriction, %{allow_historical_data: true})

      cache_resolve(&GithubResolver.dev_activity/3)
    end

    @desc "Fetch the current data for a Twitter account (currently includes only Twitter followers)."
    field :twitter_data, :twitter_data do
      arg(:ticker, non_null(:string))

      cache_resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Fetch historical data for a Twitter account (currently includes only Twitter followers)."
    field :history_twitter_data, list_of(:twitter_data) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "")

      cache_resolve(&TwitterResolver.history_twitter_data/3)
    end

    @desc ~s"""
    Fetch burn rate for a project within a given time period, grouped by interval.
    Projects are referred to by a unique identifier (slug).

    Each transaction has an equivalent burn rate record. The burn rate is calculated
    by multiplying the number of tokens moved by the number of blocks in which they appeared.
    Spikes in burn rate could indicate large transactions or movement of tokens that have been held for a long time.

    Grouping by interval works by summing all burn rate records in the interval.
    """
    field :burn_rate, list_of(:burn_rate_data) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "")

      middleware(ApiTimeframeRestriction)
      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&EtherbiResolver.token_age_consumed/3)
    end

    field :token_age_consumed, list_of(:token_age_consumed_data) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "")

      middleware(ApiTimeframeRestriction)
      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&EtherbiResolver.token_age_consumed/3)
    end

    @desc ~s"""
    Fetch total amount of tokens for a project that were transacted on the blockchain, grouped by interval.
    Projects are referred to by a unique identifier (slug).

    This metric includes only on-chain volume, not volume in exchanges.

    Grouping by interval works by summing all transaction volume records in the interval.
    """
    field :transaction_volume, list_of(:transaction_volume) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "")

      middleware(ApiTimeframeRestriction)
      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&EtherbiResolver.transaction_volume/3)
    end

    @desc ~s"""
    Fetch token age consumed in days for a project, grouped by interval.
    Projects are referred to by a unique identifier (slug). The token age consumed
    in days shows the average age of the tokens that were transacted for a given time period.

    This metric includes only on-chain transaction volume, not volume in exchanges.
    """
    field :average_token_age_consumed_in_days, list_of(:token_age) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      middleware(ApiTimeframeRestriction)
      complexity(&Complexity.from_to_interval/3)

      cache_resolve(&EtherbiResolver.average_token_age_consumed_in_days/3)
    end

    @desc ~s"""
    Fetch token circulation for a project, grouped by interval.
    Projects are referred to by a unique identifier (slug).
    """
    field :token_circulation, list_of(:token_circulation) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      @desc "The interval should represent whole days, i.e. `1d`, `48h`, `1w`, etc."
      arg(:interval, :string, default_value: "1d")

      middleware(ApiTimeframeRestriction)
      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&EtherbiResolver.token_circulation/3)
    end

    @desc ~s"""
    Fetch daily active addresses for a project within a given time period.
    Projects are referred to by a unique identifier (slug).

    This metric includes the number of unique addresses that participated in
    the transfers of given token during the day.

    Grouping by interval works by taking the mean of all daily active address
    records in the interval. The default value of the interval is 1 day, which yields
    the exact number of unique addresses for each day.
    """
    field :daily_active_addresses, list_of(:active_addresses) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "")

      middleware(ApiTimeframeRestriction, %{allow_historical_data: true})
      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&EtherbiResolver.daily_active_addresses/3)
    end

    @desc "Fetch the currently running poll."
    field :current_poll, :poll do
      cache_resolve(&VotingResolver.current_poll/3)
    end

    @desc ~s"""
    Fetch the post with the given ID.
    The user must be logged in to access all fields for the post/insight.
    """
    field :post, :post do
      arg(:id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.post/3)
    end

    @desc "Fetch a list of all posts/insights. The user must be logged in to access all fields for the post/insight."
    field :all_insights, list_of(:post) do
      middleware(PostPermissions)
      resolve(&PostResolver.all_insights/3)
    end

    @desc "Fetch a list of all posts for given user ID."
    field :all_insights_for_user, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_for_user/3)
    end

    @desc "Fetch a list of all posts for which a user has voted."
    field :all_insights_user_voted, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_user_voted_for/3)
    end

    @desc ~s"""
    Fetch a list of all posts/insights that have a given tag.
    The user must be logged in to access all fields for the post/insight.
    """
    field :all_insights_by_tag, list_of(:post) do
      arg(:tag, non_null(:string))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_by_tag/3)
    end

    @desc "Fetch a list of all tags used for posts/insights. This query also returns tags that are not yet in use."
    field :all_tags, list_of(:tag) do
      cache_resolve(&PostResolver.all_tags/3)
    end

    @desc ~s"""
    Fetch the flow of funds into and out of an exchange wallet.
    This query returns the difference IN-OUT calculated for each interval.
    """
    field :exchange_funds_flow, list_of(:exchange_funds_flow) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "")

      middleware(ApiTimeframeRestriction)

      cache_resolve(&EtherbiResolver.exchange_funds_flow/3)
    end

    @desc ~s"""
    Fetch the exchange funds flow for all ERC20 projects in the given interval.

    Arguments description:
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-05-23T10:02:19Z"

    Fields description:
      * ticker - The ticker of the project
      * contract - The contract identifier of the project
      * exchangeIn - How many tokens were deposited in the given period
      * exchangeOut - How many tokens were withdrawn in the given period
      * exchangeDiff - The difference between the deposited and the withdrawn tokens: exchangeIn - exchangeOut
      * exchangeInUsd - How many tokens were deposited in the given period converted to USD based on the daily average price of the token
      * exchangeOutUsd - How many tokens were withdrawn in the given period converted to USD based on the daily average price of the token
      * exchangeDiffUsd - The difference between the deposited and the withdrawn tokens in USD: exchangeInUsd - exchangeOutUsd
      * percentDiffExchangeDiffUsd - The percent difference between exchangeDiffUsd for the current period minus the exchangeDiffUsd for the previous period based on exchangeDiffUsd for the current period: (exchangeDiffUsd for current period - exchangeDiffUsd for previous period) * 100 / abs(exchangeDiffUsd for current period)
      * exchangeVolumeUsd - The volume of all tokens in and out for the given period in USD: exchangeInUsd + exchangeOutUsd
      * percentDiffExchangeVolumeUsd - The percent difference between exchangeVolumeUsd for the current period minus the exchangeVolumeUsd for the previous period based on exchangeVolumeUsd for the current period: (exchangeVolumeUsd for current period - exchangeVolumeUsd for previous period) * 100 / abs(exchangeVolumeUsd for current period)
      * exchangeInBtc - How many tokens were deposited in the given period converted to BTC based on the daily average price of the token
      * exchangeOutBtc - How many tokens were withdrawn in the given period converted to BTC based on the daily average price of the token
      * exchangeDiffBtc - The difference between the deposited and the withdrawn tokens in BTC: exchangeInBtc - exchangeOutBtc
      * percentDiffExchangeDiffBtc - The percent difference between exchangeDiffBtc for the current period minus the exchangeDiffBtc for the previous period based on exchangeDiffBtc for the current period: (exchangeDiffBtc for current period - exchangeDiffBtc for previous period) * 100 / abs(exchangeDiffBtc for current period)
      * exchangeVolumeBtc - The volume of all tokens in and out for the given period in BTC: exchangeInBtc + exchangeOutBtc
      * percentDiffExchangeVolumeBtc - The percent difference between exchangeVolumeBtc for the current period minus the exchangeVolumeBtc for the previous period based on exchangeVolumeBtc for the current period: (exchangeVolumeBtc for current period - exchangeVolumeBtc for previous period) * 100 / abs(exchangeVolumeBtc for current period)
    """
    field :erc20_exchange_funds_flow, list_of(:erc20_exchange_funds_flow) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      middleware(ApiTimeframeRestriction)

      cache_resolve(&TechIndicatorsResolver.erc20_exchange_funds_flow/3)
    end

    @desc ~s"""
    Fetch the price-volume difference technical indicator for a given ticker, display currency and time period.
    This indicator measures the difference in trend between price and volume,
    specifically when price goes up as volume goes down.
    """
    field :price_volume_diff, list_of(:price_volume_diff) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported currencies: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      middleware(ApiTimeframeRestriction)

      complexity(&TechIndicatorsComplexity.price_volume_diff/3)
      cache_resolve(&TechIndicatorsResolver.price_volume_diff/3)
    end

    @desc "Fetch the Twitter mention count for a given ticker and time period."
    field :twitter_mention_count, list_of(:twitter_mention_count) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.twitter_mention_count/3)
      cache_resolve(&TechIndicatorsResolver.twitter_mention_count/3)
    end

    @desc ~s"""
    Fetch the emoji sentiment for a given ticker and time period.
    This metric is a basic sentiment analysis, based on emojis used in social media.
    """
    field :emojis_sentiment, list_of(:emojis_sentiment) do
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      middleware(MultipleAuth, [
        {JWTAuth, san_tokens: 1000},
        {ApikeyAuth, san_tokens: 1000}
      ])

      complexity(&TechIndicatorsComplexity.emojis_sentiment/3)
      cache_resolve(&TechIndicatorsResolver.emojis_sentiment/3)
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
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, non_null(:string), default_value: "1d")
      arg(:social_volume_type, non_null(:social_volume_type))

      middleware(ApiTimeframeRestriction)

      complexity(&TechIndicatorsComplexity.social_volume/3)
      resolve(&TechIndicatorsResolver.social_volume/3)
    end

    @desc ~s"""
    Returns a list of slugs for which there is social volume data.
    """
    field :social_volume_projects, list_of(:string) do
      resolve(&TechIndicatorsResolver.social_volume_projects/3)
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

      middleware(ApiTimeframeRestriction)

      complexity(&TechIndicatorsComplexity.topic_search/3)
      resolve(&TechIndicatorsResolver.topic_search/3)
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

      middleware(ApiTimeframeRestriction)

      cache_resolve(&SocialDataResolver.trending_words/3)
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

      middleware(ApiTimeframeRestriction)

      cache_resolve(&SocialDataResolver.word_context/3)
    end

    @desc "Fetch a list of all exchange wallets. This query requires basic authentication."
    field :exchange_wallets, list_of(:wallet) do
      middleware(BasicAuth)

      cache_resolve(&EtherbiResolver.exchange_wallets/3)
    end

    @desc "Fetch the ETH spent by all ERC20 projects within a given time period."
    field :eth_spent_by_erc20_projects, :float do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&ProjectTransactionsResolver.eth_spent_by_erc20_projects/3)
    end

    @desc ~s"""
    Fetch ETH spent by all projects within a given time period and interval.
    This query returns a list of values where each value is of length `interval`.
    """
    field :eth_spent_over_time_by_erc20_projects, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&ProjectTransactionsResolver.eth_spent_over_time_by_erc20_projects/3)
    end

    @desc "Fetch all favourites lists for current_user."
    field :fetch_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_user_lists/3)
    end

    @desc "Fetch all public favourites lists for current_user."
    field :fetch_public_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_public_user_lists/3)
    end

    @desc "Fetch all public favourites lists"
    field :fetch_all_public_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_all_public_user_lists/3)
    end

    @desc ~s"""
    Fetch public favourites list by list id.
    If the list is owned by the current user then the list can be private as well.
    This query returns either a single user list item or null.
    """
    field :user_list, :user_list do
      arg(:user_list_id, non_null(:id))

      resolve(&UserListResolver.user_list/3)
    end

    @desc "Returns statistics for the data stored in elasticsearch"
    field :elasticsearch_stats, :elasticsearch_stats do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&ElasticsearchResolver.stats/3)
    end

    @desc ~s"""
    Historical balance for erc20 token or eth address.
    Returns the historical balance for a given address in the given interval.
    """
    field :historical_balance, list_of(:historical_balance) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:address, non_null(:string))
      arg(:interval, non_null(:string), default_value: "1d")

      cache_resolve(&ClickhouseResolver.historical_balance/3)
    end

    @desc "List all exchanges"
    field :all_exchanges, list_of(:string) do
      cache_resolve(&ExchangeResolver.all_exchanges/3)
    end

    @desc ~s"""
    Calculates the exchange inflow and outflow volume in usd for a given exchange in a time interval.
    """
    field :exchange_volume, list_of(:exchange_volume) do
      arg(:exchange, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&ExchangeResolver.exchange_volume/3)
    end

    @desc "Network growth returns the newly created addresses for a project in a given timeframe"
    field :network_growth, list_of(:network_growth) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")

      middleware(ApiTimeframeRestriction)

      cache_resolve(&ClickhouseResolver.network_growth/3)
    end
  end

  mutation do
    field :eth_login, :login do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      resolve(&AccountResolver.eth_login/2)
    end

    field :email_login, :email_login_request do
      arg(:email, non_null(:string))
      arg(:username, :string)
      arg(:consent, :string)

      resolve(&AccountResolver.email_login/2)
    end

    field :email_login_verify, :login do
      arg(:email, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_login_verify/2)
    end

    field :email_change_verify, :login do
      arg(:email_candidate, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_change_verify/2)
    end

    field :change_email, :email_login_request do
      arg(:email, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_email/3)
    end

    field :change_username, :user do
      arg(:username, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_username/3)
    end

    field :vote, :post do
      arg(:post_id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&VotingResolver.vote/3)
    end

    field :unvote, :post do
      arg(:post_id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&VotingResolver.unvote/3)
    end

    @desc "Create a post."
    field :create_post, :post do
      arg(:title, non_null(:string))
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))

      middleware(JWTAuth)
      resolve(&PostResolver.create_post/3)
    end

    @desc "Update a post."
    field :update_post, :post do
      arg(:id, non_null(:id))
      arg(:title, :string)
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))

      middleware(JWTAuth)
      resolve(&PostResolver.update_post/3)
    end

    @desc "Delete a post. The post must be owned by the user currently logged in."
    field :delete_post, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&PostResolver.delete_post/3)
    end

    @desc "Upload a list of images and return their URLs."
    field :upload_image, list_of(:image_data) do
      arg(:images, list_of(:upload))

      middleware(JWTAuth)
      resolve(&FileResolver.upload_image/3)
    end

    @desc "Publish insight."
    field :publish_insight, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&PostResolver.publish_insight/3)
    end

    @desc ~s"""
    Update the terms and condition the user accepts. The `accept_privacy_policy`
    must be accepted (must equal `true`) in order for the account to be considered
    activated.
    """
    field :update_terms_and_conditions, :user do
      arg(:privacy_policy_accepted, :boolean)
      arg(:marketing_accepted, :boolean)

      # Allow this mutation to be executed when the user has not accepted the privacy policy.
      middleware(JWTAuth, allow_access: true)
      resolve(&AccountResolver.update_terms_and_conditions/3)
    end

    @desc ~s"""
    Generates a new apikey. There could be more than one apikey per user at every
    given time. Only JWT authenticated users can generate apikeys. The apikeys can
     be retrieved via the `apikeys` fields of the `user` GQL type.
    """
    field :generate_apikey, :user do
      middleware(JWTAuth)
      resolve(&ApikeyResolver.generate_apikey/3)
    end

    @desc ~s"""
    Revoke the given apikey if only the currently logged in user is the owner of the
    apikey. Only JWT authenticated users can revoke apikeys. You cannot revoke the apikey
    using the apikey.
    """
    field :revoke_apikey, :user do
      arg(:apikey, non_null(:string))

      middleware(JWTAuth)
      resolve(&ApikeyResolver.revoke_apikey/3)
    end

    @desc """
    Create user favourites list.
    """

    field :create_user_list, :user_list do
      arg(:name, non_null(:string))
      arg(:is_public, :boolean)
      arg(:color, :color_enum)

      middleware(JWTAuth)
      resolve(&UserListResolver.create_user_list/3)
    end

    @desc """
    Update user favourites list.
    """

    field :update_user_list, :user_list do
      arg(:id, non_null(:integer))
      arg(:name, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:list_items, list_of(:input_list_item))

      middleware(JWTAuth)
      resolve(&UserListResolver.update_user_list/3)
    end

    @desc """
    Remove user favourites list.
    """

    field :remove_user_list, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserListResolver.remove_user_list/3)
    end
  end
end
