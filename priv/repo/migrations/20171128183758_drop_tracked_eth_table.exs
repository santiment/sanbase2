defmodule Sanbase.Repo.Migrations.DropTrackedEthTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    drop(table(:tracked_eth))
  end
end
