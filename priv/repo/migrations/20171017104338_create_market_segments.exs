defmodule Sanbase.Repo.Migrations.CreateMarketSegments do
  use Ecto.Migration

  def change do
    create table(:market_segments) do
      add :name, :string, null: false
    end

    create unique_index(:market_segments, [:name])

  end
end
