defmodule Sanbase.Repo.Migrations.AddCascadeDeletePresignedS3UrlsAttempts do
  use Ecto.Migration

  def up do
    drop(constraint(:presigned_s3_urls, "presigned_s3_urls_user_id_fkey"))

    alter table(:presigned_s3_urls) do
      modify(:user_id, references(:users, on_delete: :delete_all))
    end
  end

  def down do
    :ok
  end
end
