defmodule Sanbase.Repo.Migrations.AddRevokedAtToUserApiKeyTokens do
  use Ecto.Migration

  # Revoking an API key sets `revoked_at` instead of deleting the token row, so
  # the record of which keys existed and when they were revoked is kept.
  def change() do
    alter table(:user_api_key_tokens) do
      add(:revoked_at, :utc_datetime)
    end
  end
end
