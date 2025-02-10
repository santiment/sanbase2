defmodule Sanbase.Repo.Migrations.AddBlockchainAddressCommentsMappingTable do
  @moduledoc false
  use Ecto.Migration

  @table :blockchain_address_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:blockchain_address_id, references(:blockchain_addresses, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one blockchain_address.
    # A blockchain_address can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:blockchain_address_id]))
  end
end
