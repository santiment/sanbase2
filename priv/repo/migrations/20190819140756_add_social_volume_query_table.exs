defmodule Sanbase.Repo.Migrations.AddSocialVolumeQueryTable do
  @moduledoc false
  use Ecto.Migration

  @table "project_social_volume_query"
  def change do
    create table(@table) do
      add(:project_id, references(:project, on_delete: :nothing), null: false)
      add(:query, :text)
    end

    create(unique_index(@table, :project_id))
  end
end
