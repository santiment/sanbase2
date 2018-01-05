defmodule Sanbase.Repo.Migrations.IcoDropIcoendPricesColumns do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      remove :usd_btc_icoend
      remove :usd_eth_icoend
    end
  end
end
