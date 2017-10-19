defmodule Sanbase.Repo.Migrations.CreateTeamMembers do
  use Ecto.Migration

  def change do
    create table(:team_members) do
      add :team_id, references(:teams), null: false
      add :country_code, references(:countries)
    end

    create index(:team_members, [:team_id])
    create index(:team_members, [:country_code])
  end
end
