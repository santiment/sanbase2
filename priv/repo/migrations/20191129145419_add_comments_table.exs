defmodule Sanbase.Repo.Migrations.AddCommentsTable do
  use Ecto.Migration

  def change do
    create table(:comments) do
      add(:content, :text)
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:parent_id, references(:comments, on_delete: :nothing))

      timestamps()
    end
  end
end
