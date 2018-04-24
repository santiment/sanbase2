defmodule Sanbase.Repo.Migrations.RestoreLostProjectData do
  use Ecto.Migration
  @disable_ddl_transaction true

  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def up do
    backup_records =
      Path.expand("project_backup.csv", __DIR__)
      |> File.stream!()
      |> CSV.decode!(headers: true)

    query =
      from(
        p in Project,
        order_by: [asc: :id]
      )

    Repo.all(query)
    |> Enum.map(fn project ->
      backup_record =
        backup_records
        |> Enum.find(fn row -> row["coinmarketcap_id"] == project.coinmarketcap_id end)

      if backup_record do
        Project.changeset(project, %{
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
