defmodule Sanbase.Repo.Migrations.AddQuestionnaireDeletedFlag do
  use Ecto.Migration

  def change do
    alter table(:questionnaires) do
      add(:is_deleted, :boolean, default: false)
    end
  end
end
