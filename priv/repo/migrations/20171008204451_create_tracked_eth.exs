defmodule Sanbase.Repo.Migrations.CreateTrackedEth do
  use Ecto.Migration

  def change do
    create table(:tracked_eth) do
      add :address, :string, unique: true
    end

  end
end
