defmodule Sanbase.Repo.Migrations.AddHideProjectOption do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:is_hidden_from_lists, :boolean, default: false)
    end
  end
end
