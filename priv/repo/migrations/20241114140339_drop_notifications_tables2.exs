defmodule Sanbase.Repo.Migrations.DropNotificationsTables2 do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(table(:notifications))
    drop(table(:notification_actions))
  end

  def down do
    :ok
  end
end
