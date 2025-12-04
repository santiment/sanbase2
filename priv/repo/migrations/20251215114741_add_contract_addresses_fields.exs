defmodule Sanbase.Repo.Migrations.AddContractAddressesFields do
  use Ecto.Migration

  def change do
    alter table(:contract_addresses) do
      add(:decimals_scrape_attempted_at, :utc_datetime, null: true)
    end
  end
end
