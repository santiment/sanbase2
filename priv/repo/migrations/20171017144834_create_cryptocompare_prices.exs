defmodule Sanbase.Repo.Migrations.CreatePrices do
  use Ecto.Migration

  def change do
    create table(:cryptocompare_prices) do
      add :id_from, :string, null: false
      add :id_to, :string, null: false
      add :price, :decimal
    end

    create unique_index(:cryptocompare_prices, [:id_from, :id_to], name: :cryptocompare_id_from_to_index)
  end
end
