defmodule Sanbase.Repo.Migrations.AddProjectDescription do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:description, :text)
    end
  end
end
