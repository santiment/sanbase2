defmodule Sanbase.Repo.Migrations.RestoreLostProjectData do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  require Logger

  @disable_ddl_transaction true

  def up do
    backup_records =
      "project_backup.csv"
      |> Path.expand(__DIR__)
      |> File.stream!()
      |> NimbleCSV.RFC4180.parse_string(skip_headers: false)

    query =
      from(
        p in Project,
        order_by: [asc: :id]
      )

    query
    |> Repo.all()
    |> Enum.map(fn project ->
      Logger.debug("Updating project #{inspect(project)}")

      backup_record =
        Enum.find(backup_records, fn row ->
          row["coinmarketcap_id"] == project.slug and project.slug != nil
        end)

      if backup_record do
        Logger.debug("Found record to recover data: #{inspect(backup_record)}")

        project
        |> Project.changeset(%{
          token_decimals: project.token_decimals || backup_record["token_decimals"],
          website_link: project.website_link || backup_record["website_link"],
          reddit_link: project.reddit_link || backup_record["reddit_link"],
          twitter_link: project.twitter_link || backup_record["twitter_link"],
          btt_link: project.btt_link || backup_record["btt_link"],
          blog_link: project.blog_link || backup_record["blog_link"],
          github_link: project.github_link || backup_record["github_link"],
          telegram_link: project.telegram_link || backup_record["telegram_link"],
          slack_link: project.slack_link || backup_record["slack_link"],
          facebook_link: project.facebook_link || backup_record["facebook_link"],
          whitepaper_link: project.whitepaper_link || backup_record["whitepaper_link"]
        })
        |> Repo.update!()
      end
    end)
  end

  def down do
    raise Ecto.MigrationError, "Irreversible migration!"
  end
end
