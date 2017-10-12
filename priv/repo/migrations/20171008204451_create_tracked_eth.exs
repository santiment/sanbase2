defmodule Sanbase.Repo.Migrations.CreateTrackedEth do
  use Ecto.Migration

  def change do
    create table(:tracked_eth, primary_key: false) do
      add :address, :text, primary_key: true
    end

  end
end
