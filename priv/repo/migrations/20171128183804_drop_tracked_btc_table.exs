defmodule Sanbase.Repo.Migrations.DropTrackedBtcTable do
  use Ecto.Migration

  def change do
    drop(table(:tracked_btc))
  end
end
