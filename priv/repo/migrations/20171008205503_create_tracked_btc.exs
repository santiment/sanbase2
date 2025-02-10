defmodule Sanbase.Repo.Migrations.CreateTrackedBtc do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:tracked_btc) do
      add(:address, :string, null: false)
    end

    create(unique_index(:tracked_btc, [:address]))
  end
end
