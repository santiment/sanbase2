defmodule Sanbase.Repo.Migrations.AddIcoTokenPrices do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      add :token_usd_ico_price, :decimal
      add :token_eth_ico_price, :decimal
      add :token_btc_ico_price, :decimal
    end
  end
end
