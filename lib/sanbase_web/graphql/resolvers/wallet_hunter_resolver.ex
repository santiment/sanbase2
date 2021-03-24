defmodule SanbaseWeb.Graphql.Resolvers.WalletHunterResolver do
  def all_wallet_hunter_proposals(_root, args, _resolution) do
    selector = args[:selector] || %{}
    {:ok, Sanbase.WalletHunters.Proposal.fetch_all(selector)}
  end
end
