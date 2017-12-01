defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.User
  alias Sanbase.Auth.EthAccount
  alias SanbaseWeb.Graphql.Resolver

  object :user do
    field :id, non_null(:id)
    field :email, :string
    field :username, :string
    field :eth_accounts, list_of(:eth_account), resolve: assoc(:eth_accounts)
  end

  object :eth_account do
    field :address, non_null(:string)
    field :san_balance, non_null(:integer) do
      resolve &EthAccount.san_balance/3
    end
  end

  object :login do
    field :token, non_null(:string)
    field :user, non_null(:user)
  end

  query do
    field :current_user, :user do
      resolve &Resolver.current_user/3
    end
  end

  mutation do
    field :eth_login, :login do
      arg :signature, non_null(:string)
      arg :address, non_null(:string)
      arg :address_hash, non_null(:string)

      resolve &Resolver.eth_login/2
    end
  end
end
