defmodule SanbaseWeb.Graphql.Resolvers.WalletHunterResolver do
  alias Sanbase.WalletHunters.Proposal

  def create_wallet_hunter_proposal(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = Map.put(args, :user_id, current_user.id)

    Proposal.create(args)
  end

  def create_wallet_hunter_proposal(_root, args, _resolution) do
    Proposal.create(args)
  end

  def all_wallet_hunter_proposals(_root, args, _resolution) do
    selector = args[:selector] || %{}
    {:ok, Sanbase.WalletHunters.Proposal.fetch_all(selector)}
  end
end
