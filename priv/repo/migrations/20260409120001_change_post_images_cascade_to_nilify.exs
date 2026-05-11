defmodule Sanbase.Repo.Migrations.ChangePostImagesCascadeToNilify do
  use Ecto.Migration

  def up do
    drop(constraint(:post_images, "post_images_post_id_fkey"))

    alter table(:post_images) do
      modify(:post_id, references(:posts, on_delete: :nilify_all))
    end
  end

  def down do
    drop(constraint(:post_images, "post_images_post_id_fkey"))

    alter table(:post_images) do
      modify(:post_id, references(:posts, on_delete: :delete_all))
    end
  end
end
