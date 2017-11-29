defmodule Sanbase.Repo.Migrations.DropTrackedEthTable do
  use Ecto.Migration

  def change do
    drop table(:tracked_eth)
  end
end
