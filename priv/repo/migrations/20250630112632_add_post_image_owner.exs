defmodule Sanbase.Repo.Migrations.AddPostImageOwner do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      add(:user_id, references(:users, on_delete: :nothing), null: true)
    end
  end
end
