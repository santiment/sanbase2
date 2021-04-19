defmodule SanbaseWeb.Graphql.Resolvers.WalletHuntersResolver do
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

  def create_wh_proposal(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = Map.put(args, :user_id, current_user.id)

    Proposal.create_proposal(args)
  end

  def create_wh_proposal(_root, args, _resolution) do
    Proposal.create_proposal(args)
  end

  def wallet_hunters_proposals(_root, args, %{context: %{auth: %{current_user: current_user}}}) do
    selector = args[:selector] || %{}
    Sanbase.WalletHunters.Proposal.fetch_all(selector, current_user)
  end

  def wallet_hunters_proposals(_root, args, _resolution) do
    selector = args[:selector] || %{}
    Sanbase.WalletHunters.Proposal.fetch_all(selector)
  end

  def wallet_hunters_proposal(_root, args, _resolution) do
    Sanbase.WalletHunters.Proposal.fetch_by_id(args.id)
  end
end
