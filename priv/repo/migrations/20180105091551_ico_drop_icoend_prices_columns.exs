defmodule Sanbase.Repo.Migrations.IcoDropIcoendPricesColumns do
  use Ecto.Migration

  def up do
    alter table(:icos) do
      remove(:usd_btc_icoend)
      remove(:usd_eth_icoend)
    end
  end

  def down do
    alter table(:icos) do
      add(:usd_btc_icoend, :decimal)
      add(:usd_eth_icoend, :decimal)
    end
  end
end
