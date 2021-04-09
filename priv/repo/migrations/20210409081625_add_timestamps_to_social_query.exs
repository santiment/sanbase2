defmodule Sanbase.Repo.Migrations.AddTimestampsToSocialQuery do
  use Ecto.Migration

  def change do
    alter table(:project_social_volume_query) do
      timestamps()
    end
  end
end
