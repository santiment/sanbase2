defmodule Sanbase.Repo.Migrations.DropTrackedBtcTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    drop(table(:tracked_btc))
  end
end
