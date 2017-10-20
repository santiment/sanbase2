defmodule Sanbase.Repo.Migrations.CreateTrackedEth do
  use Ecto.Migration

  def change do
    create table(:tracked_eth) do
      add :address, :string, null: false
    end

    create unique_index(:tracked_eth, [:address])

  end
end
