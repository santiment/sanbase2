defmodule Sanbase.Repo.Migrations.AddWalletHuntersProposalsCommentsMappingTable do
  @moduledoc false
  use Ecto.Migration

  @table :wallet_hunters_proposals_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:proposal_id, references(:wallet_hunters_proposals, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one blockchain_address.
    # A blockchain_address can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:proposal_id]))
  end
end
