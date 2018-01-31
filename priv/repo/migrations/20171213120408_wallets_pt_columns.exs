defmodule Sanbase.Repo.Migrations.WalletsPtColumns do
  use Ecto.Migration

  def change do
    alter table(:project_btc_address) do
      add(:project_transparency, :boolean, null: false, default: false)
    end

    alter table(:project_eth_address) do
      add(:project_transparency, :boolean, null: false, default: false)
    end
  end
end
