defmodule Sanbase.Repo.Migrations.AddDiscordLinkToProjects do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:discord_link, :string)
    end
  end
end
