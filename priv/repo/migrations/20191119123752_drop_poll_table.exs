defmodule Sanbase.Repo.Migrations.DropPollTable do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(table(:polls))
  end

  def down do
    :ok
  end
end
