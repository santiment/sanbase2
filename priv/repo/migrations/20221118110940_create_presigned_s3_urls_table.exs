defmodule Sanbase.Repo.Migrations.CreatePresignedS3UrlsTable do
  use Ecto.Migration

  @table :presigned_s3_urls
  def change do
    create table(@table) do
      add(:user_id, references(:users), null: false)
      add(:bucket, :string, null: false)
      add(:object, :string, null: false)
      add(:presigned_url, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(@table, [:user_id, :bucket, :object]))
  end
end
