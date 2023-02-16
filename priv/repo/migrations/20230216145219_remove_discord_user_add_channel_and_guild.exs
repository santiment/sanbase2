defmodule Sanbase.Repo.Migrations.RemoveDiscordUserAddChannelAndGuild do
  use Ecto.Migration

  def change do
    alter table(:discord_dashboards) do
      remove(:discord_user)
      add(:channel_name, :string)
      add(:guild_name, :string)
    end
  end
end
