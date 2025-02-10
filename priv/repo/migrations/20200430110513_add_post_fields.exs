defmodule Sanbase.Repo.Migrations.AddPostFields do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:metrics, {:array, :string}, default: [])
      add(:prediction, :string, default: nil)
      add(:price_chart_project_id, references(:project))
    end
  end
end
