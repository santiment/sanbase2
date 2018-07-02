defmodule SanbaseWeb.Graphql.AccountTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql.Resolvers.{
    ApikeyResolver,
    AccountResolver,
    EthAccountResolver
  }

  object :user do
    field(:id, non_null(:id))
    field(:email, :string)
    field(:username, :string)
    field(:consent_id, :string)
    field(:privacy_policy_accepted, :boolean)
    field(:marketing_accepted, :boolean)

    field :san_balance, :float do
      resolve(&AccountResolver.san_balance/3)
    end

    field(:eth_accounts, list_of(:eth_account), resolve: assoc(:eth_accounts))

    field :followed_projects, list_of(:project) do
      resolve(&AccountResolver.followed_projects/3)
    end

    field :apikeys, list_of(:string) do
      resolve(&ApikeyResolver.apikeys_list/3)
    end
  end

  @desc ~s"""
  A type describing an Ethereum address. Beside the address itself it returns
  the SAN balance of that address.
  """
  object :eth_account do
    field(:address, non_null(:string))

    field :san_balance, non_null(:integer) do
      resolve(&EthAccountResolver.san_balance/3)
    end
  end

  object :post_author do
    field(:id, non_null(:id))
    field(:username, :string)
  end

  object :login do
    field(:token, non_null(:string))
    field(:user, non_null(:user))
  end

  object :email_login_request do
    field(:success, non_null(:boolean))
  end
end
