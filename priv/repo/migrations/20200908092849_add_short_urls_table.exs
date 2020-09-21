defmodule Sanbase.Repo.Migrations.AddShortUrlsTable do
  use Ecto.Migration

  def change do
    create table(:short_urls) do
      add(:short_url, :string, null: false)
      add(:full_url, :text, null: false)
      add(:user_id, references(:users), null: true)

      timestamps()
    end

    create(unique_index(:short_urls, [:short_url]))
  end
end
