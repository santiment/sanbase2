defmodule Sanbase.Repo.Migrations.ExtendProjectsWithMultichain do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:multichain_project_group_key, :string, null: true, default: nil)
      add(:deployed_on_ecosystem_id, references(:ecosystems), null: true)
    end
  end
end
