defmodule Sanbase.Repo.Migrations.CreateExchangeMarketPairMappings do
  use Ecto.Migration

  def change do
    create table(:exchange_market_pair_mappings) do
      add(:exchange, :string)
      add(:market_pair, :string)
      add(:from_ticker, :string)
      add(:to_ticker, :string)
      add(:from_slug, :string)
      add(:to_slug, :string)
      add(:source, :string)

      timestamps()
    end
  end
end
