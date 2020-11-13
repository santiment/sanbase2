defmodule Sanbase.Repo.Migrations.ExtendListItemsTable do
  use Ecto.Migration

  @table :list_items
  def change do
    alter table(@table) do
      add(:blockchain_address_user_pair_id, references(:blockchain_address_user_pairs))
    end
  end
end
