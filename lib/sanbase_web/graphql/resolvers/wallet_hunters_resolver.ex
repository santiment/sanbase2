defmodule SanbaseWeb.Graphql.Resolvers.WalletHuntersResolver do
  import Absinthe.Resolution.Helpers
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.WalletHunters.Proposal
  alias Sanbase.WalletHunters.Vote

  alias SanbaseWeb.Graphql.SanbaseDataloader

  def create_wallet_hunter_proposal(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = Map.put(args, :user_id, current_user.id)

    Proposal.create(args)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, message: changeset_errors_string(changeset)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_wh_proposal(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = Map.put(args, :user_id, current_user.id)

    Proposal.create_proposal(args)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, message: changeset_errors_string(changeset)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def wallet_hunters_vote(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = Map.put(args, :user_id, current_user.id)

    Vote.vote(args)
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

  def proposal_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_proposal_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_proposal_id, id)}
    end)
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :wallet_hunters_proposals_comments_count, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(loader, SanbaseDataloader, :wallet_hunters_proposals_comments_count, id) ||
         0}
    end)
  end
end
