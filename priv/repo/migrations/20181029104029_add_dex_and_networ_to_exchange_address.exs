defmodule Sanbase.Repo.Migrations.AddDexAndNetworToExchangeAddress do
  use Ecto.Migration

  def change do
    alter table(:exchange_eth_addresses) do
      add(:is_dex, :boolean)
      add(:infrastructure_id, references(:infrastructures))
    end
  end
end
