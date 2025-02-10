defmodule Sanbase.Repo.Migrations.ExtendListItemsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:list_items) do
      add(:blockchain_address_user_pair_id, references(:blockchain_address_user_pairs))
    end

    create(unique_index(:list_items, [:user_list_id, :blockchain_address_user_pair_id]))
    create(unique_index(:list_items, [:user_list_id, :project_id]))

    fk_check = """
    (CASE WHEN blockchain_address_user_pair_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN project_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    create(constraint(:list_items, :only_one_fk, check: fk_check))
  end
end
