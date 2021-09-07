defmodule Sanbase.Comment.WalletHuntersProposalComment do
  @moduledoc ~s"""
  A mapping table connecting comments and wallet hunters proposals.
  """
  use Ecto.Schema

  import Ecto.{Query, Changeset}

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

  def has_type?(comment_id) do
    from(pc in __MODULE__, where: pc.comment_id == ^comment_id)
    |> Sanbase.Repo.one()
    |> case do
      %__MODULE__{} -> true
      _ -> false
    end
  end
end
