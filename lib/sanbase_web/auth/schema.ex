defmodule SanbaseWeb.Auth.Schema do
  use Absinthe.Schema

  alias Sanbase.Auth.User
  alias Sanbase.Auth.EthAccount
  alias SanbaseWeb.Auth.Resolver

  object :user do
    field :id, non_null(:id)
    field :email, :string
    field :username, :string
  end

  object :login do
    field :token, non_null(:string)
    field :user, non_null(:user)
  end

  query do
    field :current_user, :user do
      resolve &Resolver.current_user/2
    end
  end

  mutation do
    field :eth_login, :login do
      arg :signature, non_null(:string)

      resolve &Resolver.eth_login/2
    end
  end
end
