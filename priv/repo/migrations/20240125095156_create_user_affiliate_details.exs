defmodule Sanbase.Repo.Migrations.CreateUserAffiliateDetails do
  use Ecto.Migration

  def change do
    create table(:user_affiliate_details) do
      add(:telegram_handle, :string, null: false)
      add(:marketing_channels, :text)
      add(:user_id, references(:users, on_delete: :nothing), unique: true)

      timestamps()
    end

    create(unique_index(:user_affiliate_details, [:user_id]))
  end
end
