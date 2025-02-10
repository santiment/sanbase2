defmodule Sanbase.Repo.Migrations.MigrateSlackLinkToDiscord do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Changeset

  alias Sanbase.Project
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    migrate_discord_links()
  end

  def down, do: :ok

  defp migrate_discord_links do
    :slack_link
    |> Project.List.projects_by_non_null_field(include_hidden: true)
    |> Enum.filter(fn %Project{slack_link: link} ->
      String.contains?(link, "discord")
    end)
    |> Enum.each(fn %Project{slack_link: link} = project ->
      project
      |> Project.changeset(%{discord_link: transform_discord_link(link)})
      |> Repo.update!()
    end)
  end

  defp transform_discord_link("https://discordapp.com/invite/" <> rest) do
    "https://discord.gg/" <> rest
  end

  defp transform_discord_link(link), do: link
end
