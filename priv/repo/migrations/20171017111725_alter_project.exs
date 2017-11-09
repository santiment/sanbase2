defmodule Sanbase.Repo.Migrations.AlterProject do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add :website_link, :string
      add :btt_link, :string
      add :facebook_link, :string
      add :github_link, :string
      add :reddit_link, :string
      add :twitter_link, :string
      add :whitepaper_link, :string
      add :blog_link, :string
      add :slack_link, :string
      add :linkedin_link, :string
      add :telegram_link, :string
      add :project_transparency, :string
      add :token_address, :string
      add :team_token_wallet, :string
      add :market_segment_id, references(:market_segments)
      add :infrastructure_id, references(:infrastructures)
    end

    create index(:project, [:market_segment_id])
    create index(:project, [:infrastructure_id])
  end
end
