defmodule Sanbase.Repo.Migrations.ModifyIndexUserSettings do
  @moduledoc false
  use Ecto.Migration

  def change do
    drop(index("user_settings", [:user_id]))
    create(unique_index("user_settings", [:user_id]))
  end
end
