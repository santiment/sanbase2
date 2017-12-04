defmodule Sanbase.Repo.Migrations.IcoFundsRaised do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      add :funds_raised_usd, :decimal
      add :funds_raised_eth, :decimal
    end
  end
end
