defmodule SanbaseWeb.Graphql.Resolvers.SanbaseNFTResolver do
  alias Sanbase.Accounts.User

  def sanbase_nft(%User{} = user, _args, _resolution) do
    {:ok, Sanbase.SmartContracts.SanbaseNFTInterface.nft_subscriptions(user)}
  end
end
