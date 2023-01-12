defmodule SanbaseWeb.Graphql.Resolvers.SanbaseNftResolver do
  alias Sanbase.Accounts.User
  alias Sanbase.SmartContracts.SanbaseNft

  def has_valid_sanbase_nft(%User{} = user, _args, _resolution) do
    user = Sanbase.Repo.preload(user, :eth_accounts)

    result =
      user.eth_accounts
      |> Enum.map(fn ea ->
        address = String.downcase(ea.address)
        SanbaseNft.has_valid_nft_subscription?(address)
      end)

    {:ok, Enum.any?(result)}
  end
end
