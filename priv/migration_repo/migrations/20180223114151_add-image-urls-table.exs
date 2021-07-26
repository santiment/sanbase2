defmodule :"Elixir.Sanbase.Repo.Migrations.Add-image-urls-table" do
  use Ecto.Migration

  def change do
    create table(:post_images) do
      add(:file_name, :text)
      add(:image_url, :text, null: false)
      add(:content_hash, :text, null: false)
      add(:hash_algorithm, :text, null: false)
      add(:post_id, references(:posts, on_delete: :delete_all))
    end

    create(unique_index(:post_images, [:image_url]))
  end
end
