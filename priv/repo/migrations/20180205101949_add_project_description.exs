defmodule Sanbase.Repo.Migrations.AddProjectDescription do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:description, :text)
    end
  end
end
