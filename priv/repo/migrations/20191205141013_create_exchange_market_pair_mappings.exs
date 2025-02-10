defmodule Sanbase.Repo.Migrations.CreateExchangeMarketPairMappings do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:exchange_market_pair_mappings) do
      add(:exchange, :string, null: false)
      add(:market_pair, :string, null: false)
      add(:from_ticker, :string, null: false)
      add(:to_ticker, :string, null: false)
      add(:from_slug, :string, null: false)
      add(:to_slug, :string, null: false)
      add(:source, :string, null: false)

      timestamps()
    end

    create(unique_index(:exchange_market_pair_mappings, [:exchange, :source, :market_pair]))
  end
end
