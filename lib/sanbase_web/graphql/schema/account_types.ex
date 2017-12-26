defmodule SanbaseWeb.Graphql.AccountTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.Resolvers.{AccountResolver, EthAccountResolver}
  alias SanbaseWeb.Graphql.ProjectTypes

  object :user do
    field :id, non_null(:id)
    field :email, :string
    field :username, :string
    field :eth_accounts, list_of(:eth_account), resolve: assoc(:eth_accounts)
    field :followed_projects, list_of(:project) do
      #TODO Redo to return list_of(:project) when there's an API for that?
      resolve &AccountResolver.followed_projects/3
    end
  end

  object :eth_account do
    field :address, non_null(:string)
    field :san_balance, non_null(:integer) do
      resolve &EthAccountResolver.san_balance/3
    end
  end

  object :login do
    field :token, non_null(:string)
    field :user, non_null(:user)
  end
end
