defmodule SanbaseWeb.Graphql.Resolvers.SanbaseNftResolver do
  alias Sanbase.Accounts.User

  def sanbase_nft(%User{} = user, _args, _resolution) do
    {:ok, Sanbase.SmartContracts.SanbaseNftInterface.nft_subscriptions(user)}
  end
end
