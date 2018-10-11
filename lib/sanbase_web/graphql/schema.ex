defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.Resolvers.AccountResolver
  alias SanbaseWeb.Graphql.Resolvers.ProjectResolver
  alias SanbaseWeb.Graphql.Middlewares.{MultipleAuth, BasicAuth, JWTAuth}

  import_types Absinthe.Type.Custom
  import_types SanbaseWeb.Graphql.AccountTypes
  import_types SanbaseWeb.Graphql.PriceTypes
  import_types SanbaseWeb.Graphql.ProjectTypes
  import_types SanbaseWeb.Graphql.GithubTypes
  import_types SanbaseWeb.Graphql.TwitterTypes
  import_types SanbaseWeb.Graphql.EtherbiTypes

  query do
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    field :all_projects, list_of(:project_listing) do
      arg :only_project_transparency, :boolean

      resolve &ProjectResolver.all_projects/3
    end

    field :project, :project_public do
      arg :id, non_null(:id)
      arg :only_project_transparency, :boolean # this is to filter the wallets

      resolve &ProjectResolver.project/3
    end

    field :all_projects_with_eth_contract_info, list_of(:project_with_eth_contract_info) do
      middleware BasicAuth
      resolve &ProjectResolver.all_projects_with_eth_contract_info/3
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

      resolve(&EtherbiResolver.burn_rate/3)
    end

    @desc "Transaction volume for a ticker and given time period"
    field :transaction_volume, list_of(:transaction_volume) do
      arg(:ticker, non_null(:string))
      arg(:from, :datetime)
      arg(:to, :datetime, default_value: DateTime.utc_now())

      resolve(&EtherbiResolver.transaction_volume/3)
    end

  end

  mutation do
    field :eth_login, :login do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      resolve(&AccountResolver.eth_login/2)
    end

    field :change_email, :user do
      arg :email, non_null(:string)

      middleware(JWTAuth)
      resolve(&AccountResolver.change_email/3)
    end

    field :follow_project, :user do
      arg :project_id, non_null(:integer)

      middleware(JWTAuth)
      resolve(&AccountResolver.follow_project/3)
    end

    field :unfollow_project, :user do
      arg :project_id, non_null(:integer)

      middleware(JWTAuth)
      resolve(&AccountResolver.unfollow_project/3)
    end
  end
end
