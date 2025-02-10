defmodule Sanbase.Repo.Migrations.AddCommentsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:comments) do
      add(:content, :text, null: false)
      add(:subcomments_count, :integer, default: 0, null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:parent_id, references(:comments, on_delete: :nothing))
      add(:root_parent_id, references(:comments, on_delete: :nothing))
      add(:edited_at, :naive_datetime)

      timestamps()
    end
  end
end
