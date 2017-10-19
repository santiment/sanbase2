defmodule Sanbase.Repo.Migrations.CreateTrackedBtc do
  use Ecto.Migration

  def change do
    create table(:tracked_btc) do
      add :address, :string, unique: true
    end

  end
end
