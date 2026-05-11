defmodule Sanbase.Repo.Migrations.AddVariantUrlsToPostImages do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      add(:image_url_w400, :text)
      add(:image_url_w800, :text)
      add(:image_url_w1200, :text)
      add(:image_url_w2000, :text)
    end
  end
end
