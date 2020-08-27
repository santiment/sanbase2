defmodule Sanbase.Repo.Migrations.AddColumnToMarketSegments do
  use Ecto.Migration

  def change do
    alter table(:market_segments) do
      add(:type, :string)
    end
  end
end
