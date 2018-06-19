defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql.Resolvers.{
    AccountResolver,
    PriceResolver,
    ProjectResolver,
    GithubResolver,
    TwitterResolver,
    EtherbiResolver,
    VotingResolver,
    TechIndicatorsResolver,
    FileResolver,
    PostResolver,
    MarketSegmentResolver
  }

  import SanbaseWeb.Graphql.Helpers.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Complexity.PriceComplexity
  alias SanbaseWeb.Graphql.Complexity.TechIndicatorsComplexity

  alias SanbaseWeb.Graphql.Middlewares.{
    BasicAuth,
    JWTAuth,
    ProjectPermissions,
    PostPermissions
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
  import_types(SanbaseWeb.Graphql.TransactionTypes)
  import_types(SanbaseWeb.Graphql.FileTypes)

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

  query do
    @desc "Returns the currently logged in user"
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    @desc "Fetch all market segments"
    field :all_market_segments, :string do
      middleware(ProjectPermissions)
      cache_resolve(&MarketSegmentResolver.all_market_segments/3)
    end

    @desc "Fetch all projects that have price data"
    field :all_projects, list_of(:project) do
      middleware(ProjectPermissions)
      cache_resolve(&ProjectResolver.all_projects/3)
    end

    @desc "Fetch all ERC20 projects"
    field :all_erc20_projects, list_of(:project) do
      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_erc20_projects/3)
    end

    @desc "Fetch all currency projects. Currency project is every project that is not classified as ERC20 and there is price data for it"
    field :all_currency_projects, list_of(:project) do
      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_currency_projects/3)
    end

    @desc "Fetch all project transparency projects. Requires basic authentication"
    field :all_projects_project_transparency, list_of(:project) do
      middleware(BasicAuth)
      resolve(&ProjectResolver.all_projects(&1, &2, &3, true))
    end

    @desc "Fetch a project by its ID"
    field :project, :project do
      arg(:id, non_null(:id))
      # this is to filter the wallets
      arg(:only_project_transparency, :boolean, default_value: false)

      middleware(ProjectPermissions)
      resolve(&ProjectResolver.project/3)
    end

    @desc "Fetch a project by an unique identifier"
    field :project_by_slug, :project do
      arg(:slug, non_null(:string))
      arg(:only_project_transparency, :boolean, default_value: false)

      middleware(ProjectPermissions)
      cache_resolve(&ProjectResolver.project_by_slug/3)
    end

    @desc "Fetch all projects that have ETH contract info"
    field :all_projects_with_eth_contract_info, list_of(:project) do
      middleware(BasicAuth)

      cache_resolve(&ProjectResolver.all_projects_with_eth_contract_info/3)
    end

    @desc "Fetch history price for a given ticker and time interval"
    field :history_price, list_of(:price_point) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")

      complexity(&PriceComplexity.history_price/3)
      cache_resolve(&PriceResolver.history_price/3)
    end

    @desc "Returns a list of available github repositories"
    field :github_availables_repos, list_of(:string) do
      cache_resolve(&GithubResolver.available_repos/3)
    end

    @desc ~s"""
    Returns a list of github activity for a given ticker and time interval.
    Arguments description:
      > interval -
      > transform - one of the following:
        1. None (default)
        2. movingAverage
      > movingAverageInterval - used only if transform is `movingAverage`.
        Returns the simple moving average of the data calculated with this argument.
    """
    field :github_activity, list_of(:activity_point) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")
      arg(:transform, :string, default_value: "None")
      arg(:moving_average_interval, :integer, default_value: 10)

      cache_resolve(&GithubResolver.activity/3)
    end

    @desc "Fetch the current data for a twitter account. Currently supports only twitter followers"
    field :twitter_data, :twitter_data do
      arg(:ticker, non_null(:string))

      cache_resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Fetch historical data for a twitter account. Currently supports only twitter followers"
    field :history_twitter_data, list_of(:twitter_data) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "6h")

      cache_resolve(&TwitterResolver.history_twitter_data/3)
    end

    @desc ~s"""
    Fetch burn rate for a project and given time period, grouped by interval.
    Projects are refered by an unique identifier (slug).

    Each transaction has an equivalent burn rate record. The burn rate is calculated
    by multiplying the number of tokens moved by the number of blocks that they were sitting.
    Spikes in burn rate indicate big transactions or movements of old tokens.

    Grouping by interval works by summing all burn rate records in the interval.
    """
    field :burn_rate, list_of(:burn_rate_data) do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      # TODO: Make non_null after removing :ticker
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1h")

      cache_resolve(&EtherbiResolver.burn_rate/3)
    end

    @desc ~s"""
    Fetch total amount of tokens for a given project that were transacted on the blockchain, grouped by interval.
    Projects are refered by an unique identifier (slug).

    This metric includes only on-chain volume and not volume in exchanges.

    Grouping by interval works by summing all transaction volume records in the interval.
    """
    field :transaction_volume, list_of(:transaction_volume) do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      # TODO: Make non_null after removing :ticker
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1h")

      cache_resolve(&EtherbiResolver.transaction_volume/3)
    end

    @desc ~s"""
    Fetch daily active addresses for a project and given time period
    Projects are refered by an unique identifier (slug).

    Daily active addresses is the number of unique addresses tha participated in
    the transfers of given token during the day.

    Grouping by interval works by taking the mean of all daily active addresses
    records in the interval. The default value of the interval is 1 day, which yields
    the exact number of unique addresses for each day.
    """
    field :daily_active_addresses, list_of(:active_addresses) do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      # TODO: Make non_null after removing :ticker
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&EtherbiResolver.daily_active_addresses/3)
    end

    @desc "Fetch the currently running poll"
    field :current_poll, :poll do
      cache_resolve(&VotingResolver.current_poll/3)
    end

    @desc ~s"""
    Fetch the post with the given ID.
    Requires user to be logged in to access all fields of the post/insight
    """
    field :post, :post do
      arg(:id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.post/3)
    end

    @desc "Fetch a list of all posts/insights. Requires user to be logged in to access all fields of the post/insight"
    field :all_insights, list_of(:post) do
      middleware(PostPermissions)
      resolve(&PostResolver.all_insights/3)
    end

    @desc "Fetch a list of all posts for given user ID"
    field :all_insights_for_user, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_for_user/3)
    end

    @desc "Fetch a list of all posts a user has voted for"
    field :all_insights_user_voted, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_user_voted_for/3)
    end

    @desc ~s"""
    Fetch a list of all posts/insights that have a given tag.
    Requires user to be logged in to access all fields of the post/insight
    """
    field :all_insights_by_tag, list_of(:post) do
      arg(:tag, non_null(:string))

      middleware(PostPermissions)
      resolve(&PostResolver.all_insights_by_tag/3)
    end

    @desc "Fetch a list of all tags used for posts/insights. Also returns tags that are not used yet"
    field :all_tags, list_of(:tag) do
      cache_resolve(&PostResolver.all_tags/3)
    end

    @desc ~s"""
    Fetch the flow of funds in/out from an exchange wallet.
    Returns the difference IN-OUT calculated for every interval
    """
    field :exchange_funds_flow, list_of(:funds_flow) do
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      # TODO: Make non_null after removing :ticker
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&EtherbiResolver.exchange_funds_flow/3)
    end

    @desc "Fetch the MACD technical indicator for a given ticker, display currency and time period"
    field :macd, list_of(:macd) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported currencies: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.macd/3)
      cache_resolve(&TechIndicatorsResolver.macd/3)
    end

    @desc "Fetch the RSI technical indicator for a given ticker, display currency and time period"
    field :rsi, list_of(:rsi) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:rsi_interval, non_null(:integer))
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.rsi/3)
      cache_resolve(&TechIndicatorsResolver.rsi/3)
    end

    @desc ~s"""
    Fetch the price-volume difference technical indicator for a given ticker, display currency and time period.
    The indicator measures when there is a difference in trends between price and volume.
    It shows the case when price goes up and volume goes down.
    """
    field :price_volume_diff, list_of(:price_volume_diff) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported currencies: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.price_volume_diff/3)
      cache_resolve(&TechIndicatorsResolver.price_volume_diff/3)
    end

    @desc "Fetch the twitter mention count for a given ticker and time period"
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
    Fetch the emojis sentiment for a ticker and time period.
    It is a basic sentiment analysis, based on emojis used in social media communications
    """
    field :emojis_sentiment, list_of(:emojis_sentiment) do
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      middleware(JWTAuth, san_tokens: 1000)

      complexity(&TechIndicatorsComplexity.emojis_sentiment/3)
      resolve(&TechIndicatorsResolver.emojis_sentiment/3)
    end

    @desc "Fetch a list of all exchange wallets. Requires basic authentication"
    field :exchange_wallets, list_of(:wallet) do
      middleware(BasicAuth)

      cache_resolve(&EtherbiResolver.exchange_wallets/3)
    end

    @desc "Fetch the ETH spent by all ERC20 projects in a given time period"
    field :eth_spent_by_erc20_projects, :float do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&ProjectResolver.eth_spent_by_erc20_projects/3)
    end

    @desc ~s"""
    Fetch ETH spent by all projects in a given time period and interval.
    Returns a list of values where each value is of length `interval`
    """
    field :eth_spent_over_time_by_erc20_projects, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&ProjectResolver.eth_spent_over_time_by_erc20_projects/3)
    end

    @desc "Fetch a list of followed projects for the currently logged in user."
    field :followed_projects, list_of(:project) do
      resolve(&AccountResolver.followed_projects/3)
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

    field :change_email, :user do
      arg(:email, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_email/3)
    end

    field :change_username, :user do
      arg(:username, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_username/3)
    end

    field :follow_project, :user do
      arg(:project_id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&AccountResolver.follow_project/3)
    end

    field :unfollow_project, :user do
      arg(:project_id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&AccountResolver.unfollow_project/3)
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

    @desc "Create a post"
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

    @desc "Update a post"
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

    @desc "Delete an existing post owned. Requires the post to be owned by the currently logged in used"
    field :delete_post, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&PostResolver.delete_post/3)
    end

    @desc "Upload a list images to S3 and get the urls to them"
    field :upload_image, list_of(:image_data) do
      arg(:images, list_of(:upload))

      middleware(JWTAuth)
      resolve(&FileResolver.upload_image/3)
    end

    @desc "Publish insight"
    field :publish_insight, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&PostResolver.publish_insight/3)
    end
  end
end
