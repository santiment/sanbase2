defmodule Sanbase.Repo.Migrations.AddColumnsDiscordDashboards do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:discord_dashboards) do
      add(:discord_user_id, :string)
      add(:discord_user_handle, :string)
      add(:discord_message_id, :string)
    end
  end
end
