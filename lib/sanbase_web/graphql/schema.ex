defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.AccountResolver

  import_types SanbaseWeb.Graphql.AccountTypes

  query do
    field :current_user, :user do
      resolve &AccountResolver.current_user/3
    end
  end

  mutation do
    field :eth_login, :login do
      arg :signature, non_null(:string)
      arg :address, non_null(:string)
      arg :message_hash, non_null(:string)

      resolve &AccountResolver.eth_login/2
    end
  end
end
