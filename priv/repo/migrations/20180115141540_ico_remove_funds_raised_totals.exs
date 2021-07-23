defmodule Sanbase.Repo.Migrations.IcoRemoveFundsRaisedTotals do
  use Ecto.Migration

  def up do
    alter table(:icos) do
      remove(:funds_raised_usd)
      remove(:funds_raised_eth)
      remove(:funds_raised_btc)
    end
  end

  def down do
    alter table(:icos) do
      add(:funds_raised_usd, :decimal)
      add(:funds_raised_eth, :decimal)
      add(:funds_raised_btc, :decimal)
    end
  end
end
