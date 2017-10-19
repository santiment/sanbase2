defmodule Sanbase.Repo.Migrations.CreatePrices do
  use Ecto.Migration

  def change do
    create table(:prices) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :price_usd, :decimal
      add :price_btc, :decimal
      add :price_eth, :decimal
    end

    create unique_index(:prices, [:project_id])
  end
end
