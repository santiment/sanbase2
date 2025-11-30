defmodule Sanbase.Repo.Migrations.CreateDiscordVerificationCodes do
  use Ecto.Migration

  def change do
    create table(:discord_verification_codes) do
      add(:code, :string, null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      # Track tier for reference
      add(:subscription_tier, :string, null: false)
      # Set when verified
      add(:discord_user_id, :string)
      # Discord username (e.g., "user#1234")
      add(:discord_username, :string)
      add(:verified_at, :utc_datetime)
      add(:expires_at, :utc_datetime, null: false)
      add(:used, :boolean, default: false)

      timestamps()
    end

    create(unique_index(:discord_verification_codes, [:code]))
    create(index(:discord_verification_codes, [:user_id]))
    create(index(:discord_verification_codes, [:discord_user_id]))
  end
end
