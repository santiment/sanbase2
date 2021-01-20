defmodule Sanbase.Repo.Migrations.MigrateSlackLinkToDiscord do
  use Ecto.Migration

  import Ecto.Changeset

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    migrate_discord_links()
  end

  def down, do: :ok

  defp migrate_discord_links() do
    Project.List.projects_by_non_null_field(
      :slack_link,
      include_hidden_projects?: true
    )
    |> Enum.filter(fn %Project{slack_link: link} ->
      String.contains?(link, "discord")
    end)
    |> Enum.map(fn %Project{slack_link: link} = project ->
      Project.changeset(project, %{discord_link: link})
      |> update_change(:discord_link, &transform_discord_link/1)
      |> Repo.update!()
    end)
  end

  defp transform_discord_link(link) do
    long_prefix = "https://discordapp.com/invite/"
    short_prefix = "https://discord.gg/"

    String.replace_prefix(link, long_prefix, short_prefix)
  end
end
