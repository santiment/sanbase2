defmodule Sanbase.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :team_website, :integer
      add :avno_linkedin_network_team, :decimal
      add :dev_people, :integer
      add :business_people, :integer
      add :real_names, :boolean
      add :pics_available, :boolean
      add :linkedin_profiles_project, :integer
      add :advisors, :integer
      add :advisor_linkedin_available, :integer
      add :av_no_linkedin_network_advisors, :integer
    end

    create unique_index(:teams, [:project_id])
  end
end
