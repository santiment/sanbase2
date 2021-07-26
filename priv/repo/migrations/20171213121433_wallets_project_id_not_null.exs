defmodule Sanbase.Repo.Migrations.WalletsProjectIdNotNull do
  use Ecto.Migration

  def up do
    alter table(:project_btc_address) do
      modify(:project_id, :bigint, null: false)
    end

    alter table(:project_eth_address) do
      modify(:project_id, :bigint, null: false)
    end
  end

  def down do
    alter table(:project_btc_address) do
      modify(:project_id, :bigint, null: true)
    end

    alter table(:project_eth_address) do
      modify(:project_id, :bigint, null: true)
    end
  end
end
