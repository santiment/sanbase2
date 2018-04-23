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
    PostResolver
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

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.PriceStore

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
    Dataloader.new()
    |> Dataloader.add_source(SanbaseRepo, SanbaseRepo.data())
    |> Dataloader.add_source(PriceStore, PriceStore.data())
  end

  def context(ctx) do
    Map.put(ctx, :loader, dataloader())
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end

  query do
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    @desc "Fetch all projects or only those in project transparency based on the argument"
    field :all_projects, list_of(:project) do
      arg(:only_project_transparency, :boolean, default_value: false)

      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_projects/3)
    end

    @desc "Fetch all ERC20 projects"
    field :all_erc20_projects, list_of(:project) do
      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_erc20_projects/3)
    end

    @desc "Fetch all currency projects"
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

    @desc "Fetch a project by a unique identifier"
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

    @desc "Historical information for the price"
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

    @desc "Returns a list of github activities"
    field :github_activity, list_of(:activity_point) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")
      arg(:moving_average_interval, :integer, default_value: 10)
      arg(:transform, :string, default_value: "None")

      cache_resolve(&GithubResolver.activity/3)
    end

    @desc "Current data for a twitter account"
    field :twitter_data, :twitter_data do
      arg(:ticker, non_null(:string))

      cache_resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Historical information for a twitter account"
    field :history_twitter_data, list_of(:twitter_data) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "6h")

      cache_resolve(&TwitterResolver.history_twitter_data/3)
    end

    @desc "Burn rate for a ticker and given time period"
    field :burn_rate, list_of(:burn_rate_data) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1h")

      cache_resolve(&EtherbiResolver.burn_rate/3)
    end

    @desc "Transaction volume for a ticker and given time period"
    field :transaction_volume, list_of(:transaction_volume) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1h")

      cache_resolve(&EtherbiResolver.transaction_volume/3)
    end

    @desc "Daily active addresses for a ticker and given time period"
    field :daily_active_addresses, list_of(:active_addresses) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&EtherbiResolver.daily_active_addresses/3)
    end

    @desc "Returns the currently running poll"
    field :current_poll, :poll do
      cache_resolve(&VotingResolver.current_poll/3)
    end

    @desc "Get the post with the specified id"
    field :post, :post do
      arg(:id, non_null(:integer))

      middleware(PostPermissions)

      cache_resolve(&PostResolver.post/3)
    end

    @desc "Get all posts"
    field :all_insights, list_of(:post) do
      middleware(PostPermissions)

      resolve(&PostResolver.all_insights/3)
    end

    @desc "Get all posts for given user"
    field :all_insights_for_user, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)

      resolve(&PostResolver.all_insights_for_user/3)
    end

    @desc "Get all posts a user has voted for"
    field :all_insights_user_voted, list_of(:post) do
      arg(:user_id, non_null(:integer))

      middleware(PostPermissions)

      resolve(&PostResolver.all_insights_user_voted_for/3)
    end

    @desc "Get all tags"
    field :all_tags, list_of(:tag) do
      cache_resolve(&PostResolver.all_tags/3)
    end

    @desc "Shows the flow of funds in an exchange wallet"
    field :exchange_funds_flow, list_of(:funds_flow) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&EtherbiResolver.exchange_funds_flow/3)
    end

    @desc "MACD for a ticker and given currency and time period"
    field :macd, list_of(:macd) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.macd/3)

      cache_resolve(&TechIndicatorsResolver.macd/3)
    end

    @desc "RSI for a ticker and given currency and time period"
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

    @desc "Price-volume diff for a ticker and given currency and time period"
    field :price_volume_diff, list_of(:price_volume_diff) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.price_volume_diff/3)

      cache_resolve(&TechIndicatorsResolver.price_volume_diff/3)
    end

    @desc "Twitter mention count for a ticker and time period"
    field :twitter_mention_count, list_of(:twitter_mention_count) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      complexity(&TechIndicatorsComplexity.twitter_mention_count/3)

      cache_resolve(&TechIndicatorsResolver.twitter_mention_count/3)
    end

    @desc "Emojis sentiment for a ticker and time period"
    field :emojis_sentiment, list_of(:emojis_sentiment) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")
      arg(:result_size_tail, :integer, default_value: 0)

      middleware(JWTAuth, san_tokens: 1000)

      complexity(&TechIndicatorsComplexity.emojis_sentiment/3)
      resolve(&TechIndicatorsResolver.emojis_sentiment/3)
    end

    @desc "Returns a list of all exchange wallets. Internal API."
    field :exchange_wallets, list_of(:wallet) do
      middleware(BasicAuth)

      cache_resolve(&EtherbiResolver.exchange_wallets/3)
    end

    @desc "Returns the ETH spent by all projects in a given time period"
    field :eth_spent_by_erc20_projects, :float do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&ProjectResolver.eth_spent_by_erc20_projects/3)
    end

    @desc "Returns the ETH spent by all projects in a given time period for a given interval"
    field :eth_spent_over_time_by_erc20_projects, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      cache_resolve(&ProjectResolver.eth_spent_over_time_by_erc20_projects/3)
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

    @desc "Mutation used for creating a post"
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

    @desc "Mutation for deleting an existing post owned by the currently logged in used"
    field :delete_post, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&PostResolver.delete_post/3)
    end

    @desc "Upload a list images and get the urls to them"
    field :upload_image, list_of(:image_data) do
      arg(:images, list_of(:upload))

      middleware(JWTAuth)
      resolve(&FileResolver.upload_image/3)
    end
  end
end
