defmodule Sanbase.Repo.Migrations.CreateHistoricalScrapePriceProgressTable do
  use Ecto.Migration

  @table :price_scraping_progress
  def change do
    create table(@table) do
      add(:identifier, :string, null: false)
      add(:datetime, :naive_datetime, null: false)
      add(:source, :string, null: false)
    end

    create(unique_index(@table, [:identifier, :source]))
  end
end
