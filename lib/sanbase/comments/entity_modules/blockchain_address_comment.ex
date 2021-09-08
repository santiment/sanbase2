defmodule Sanbase.Comment.BlockchainAddressComment do
  @moduledoc ~s"""
  A mapping table connecting comments and blockchain comments.

  This module is used to create, update, delete and fetch
  blockchain address comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "blockchain_address_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:blockchain_address, Sanbase.BlockchainAddress)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:blockchain_address_id, :comment_id])
    |> validate_required([:blockchain_address_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end
