defmodule Sanbase.Repo.Migrations.AddLongDescriptionToProjects do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:long_description, :text)
    end
  end
end
