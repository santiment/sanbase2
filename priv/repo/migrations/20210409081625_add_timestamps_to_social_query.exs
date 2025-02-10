defmodule Sanbase.Repo.Migrations.AddTimestampsToSocialQuery do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project_social_volume_query) do
      # Adding timestamps to an existing table requires a default value
      # otherwise a non-null violation error will be raised. There is no single
      # proper value that will fit all existing fields, so today's value is used
      timestamps(default: fragment("NOW()"), null: false)
    end
  end
end
