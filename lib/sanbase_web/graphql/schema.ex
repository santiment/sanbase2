defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.{AccountResolver, PriceResolver}

  import_types SanbaseWeb.Graphql.AccountTypes
  import_types SanbaseWeb.Graphql.PriceTypes
  import_types Absinthe.Type.Custom

  query do
    field :current_user, :user do
      resolve &AccountResolver.current_user/3
    end

    @desc "Historical information for the price"
    field :history_price, list_of(:price_point) do
      arg :ticker, non_null(:string)
      arg :from, non_null(:datetime)
      arg :to, non_null(:datetime)
      arg :interval, :string

      resolve &PriceResolver.history_price/3
    end

    @desc "Current price for a ticker"
    field :price, :price_point do
      arg :ticker, non_null(:string)

      resolve &PriceResolver.current_price/3
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
