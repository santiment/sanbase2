defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.Resolvers.AccountResolver
  alias SanbaseWeb.Graphql.Resolvers.ProjectResolver
  alias SanbaseWeb.Graphql.Middlewares.{MultipleAuth, BasicAuth, JWTAuth}
  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.PriceStore

  import_types(Absinthe.Type.Custom)
  import_types(SanbaseWeb.Graphql.AccountTypes)
  import_types(SanbaseWeb.Graphql.PriceTypes)
  import_types(SanbaseWeb.Graphql.ProjectTypes)
  import_types(SanbaseWeb.Graphql.GithubTypes)
  import_types(SanbaseWeb.Graphql.TwitterTypes)
  import_types(SanbaseWeb.Graphql.EtherbiTypes)
  import_types(SanbaseWeb.Graphql.VotingTypes)
  import_types(SanbaseWeb.Graphql.TechIndicatorsTypes)

  def context(ctx) do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(SanbaseRepo, SanbaseRepo.data())
      |> Dataloader.add_source(PriceStore, PriceStore.data())

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end

  query do
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    field :all_projects, list_of(:project_listing) do
      arg(:only_project_transparency, :boolean)

      resolve(&ProjectResolver.all_projects/3)
    end

    field :all_projects_project_transparency, list_of(:project_project_transparency_listing) do
      middleware(BasicAuth)
      resolve(&ProjectResolver.all_projects(&1, &2, &3, true))
    end

    field :project, :project_public do
      arg(:id, non_null(:id))
      # this is to filter the wallets
      arg(:only_project_transparency, :boolean)

      resolve(&ProjectResolver.project/3)
    end

    field :project_full, :project_full do
      arg(:id, non_null(:id))
      # this is to filter the wallets
      arg(:only_project_transparency, :boolean)

      middleware(MultipleAuth, [BasicAuth, JWTAuth])
      resolve(&ProjectResolver.project/3)
    end

    field :all_projects_with_eth_contract_info, list_of(:project_with_eth_contract_info) do
      middleware(BasicAuth)
      resolve(&ProjectResolver.all_projects_with_eth_contract_info/3)
    end

    @desc "Historical information for the price"
    field :history_price, list_of(:price_point) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")

      complexity(&PriceComplexity.history_price/3)
      resolve(&PriceResolver.history_price/3)
    end

    @desc "Current price for a ticker"
    field :price, :price_point do
      arg(:ticker, non_null(:string))

      resolve(&PriceResolver.current_price/3)
    end

    @desc "Current price for a list of tickers"
    field :prices, list_of(:price_point) do
      arg(:tickers, non_null(list_of(:string)))

      complexity(&PriceComplexity.current_prices/3)
      resolve(&PriceResolver.current_prices/3)
    end

    @desc "Returns a list of available tickers"
    field :available_prices, list_of(:string) do
      resolve(&PriceResolver.available_prices/3)
    end

    @desc "Returns a list of available github repositories"
    field :github_availables_repos, list_of(:string) do
      resolve(&GithubResolver.available_repos/3)
    end

    @desc "Returns a list of github activities"
    field :github_activity, list_of(:activity_point) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")
      arg(:moving_average_interval, :integer, default_value: 10)
      arg(:transform, :string, default_value: "None")

      resolve(&GithubResolver.activity/3)
    end

    @desc "Current data for a twitter account"
    field :twitter_data, :twitter_data do
      arg(:ticker, non_null(:string))

      resolve(&TwitterResolver.twitter_data/3)
    end

    @desc "Historical information for a twitter account"
    field :history_twitter_data, list_of(:twitter_data) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "6h")

      resolve(&TwitterResolver.history_twitter_data/3)
    end

    @desc "Burn rate for a ticker and given time period"
    field :burn_rate, list_of(:burn_rate_data) do
      arg(:ticker, non_null(:string))
      arg(:from, :datetime)
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")

      resolve(&EtherbiResolver.burn_rate/3)
    end

    @desc "Transaction volume for a ticker and given time period"
    field :transaction_volume, list_of(:transaction_volume) do
      arg(:ticker, non_null(:string))
      arg(:from, :datetime)
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1h")

      resolve(&EtherbiResolver.transaction_volume/3)
    end

    @desc "Returns the currently running poll"
    field :current_poll, :poll do
      resolve(&VotingResolver.current_poll/3)
    end

    @desc "Shows the flow of funds in an exchange wallet"
    field :exchange_fund_flow, list_of(:transaction) do
      arg(:ticker, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:transaction_type, :transaction_type, default_value: :all)

      resolve(&EtherbiResolver.exchange_fund_flow/3)
    end

    @desc "MACD for a ticker and given currency and time period"
    field :macd, list_of(:macd) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")

      complexity(&TechIndicatorsComplexity.macd/3)
      resolve(&TechIndicatorsResolver.macd/3)
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

      complexity(&TechIndicatorsComplexity.rsi/3)
      resolve(&TechIndicatorsResolver.rsi/3)
    end

    @desc "Price-volume diff for a ticker and given currency and time period"
    field :price_volume_diff, list_of(:price_volume_diff) do
      arg(:ticker, non_null(:string))
      @desc "Currently supported: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, :datetime, default_value: DateTime.utc_now())
      arg(:interval, :string, default_value: "1d")

      complexity(&TechIndicatorsComplexity.price_volume_diff/3)
      resolve(&TechIndicatorsResolver.price_volume_diff/3)
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

    field :create_post, :post do
      arg(:title, non_null(:string))
      arg(:link, non_null(:string))

      middleware(JWTAuth)
      resolve(&VotingResolver.create_post/3)
    end

    field :delete_post, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&VotingResolver.delete_post/3)
    end
  end
end
