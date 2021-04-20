defmodule Sanbase.WalletHunters.ProposalComment do
  @moduledoc ~s"""
  A mapping table connecting comments and wallet hunters proposals.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Comment
  alias Sanbase.WalletHunters.Proposal

  schema "wallet_hunters_proposals_comments_mapping" do
    belongs_to(:comment, Comment)
    belongs_to(:proposal, Proposal)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:proposal_id, :comment_id])
    |> validate_required([:proposal_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end
