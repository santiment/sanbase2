defmodule Sanbase.Repo.Migrations.RemoveNonnullConstraintForCoinmarketcapId do
  use Ecto.Migration

  def up do
    alter table("project") do
      modify :coinmarketcap_id, :string, null: true
    end

    drop unique_index(:project, [:coinmarketcap_id])
  end

  def down do
    alter table("project") do
      modify :coinmarketcap_id, :string, null: false
    end

    create unique_index(:project, [:coinmarketcap_id])
  end

end
