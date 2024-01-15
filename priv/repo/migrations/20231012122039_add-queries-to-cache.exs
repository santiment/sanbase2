defmodule :"Elixir.Sanbase.Repo.Migrations.Add-queries-to-cache" do
  use Ecto.Migration

  def change do
    alter table(:dashboards_cache) do
      # Add capabilities to store queries
      add(:queries, :map, default: %{}, null: true)
      # Allow the panels to be null now that we'll store queries
      modify(:panels, :map, default: %{}, null: true)
    end
  end
end
