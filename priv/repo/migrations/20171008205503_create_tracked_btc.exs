defmodule Sanbase.Repo.Migrations.CreateTrackedBtc do
  use Ecto.Migration

  def change do
    create table(:tracked_btc, primary_key: false) do
      add :address, :text, primary_key: true
    end

  end
end
