defmodule Sanbase.Repo.Migrations.AddNewNotificationsTables do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add(:action, :string)
      add(:params, :map)
      add(:channels, {:array, :string})
      add(:step, :string)
      add(:processed_for_discord, :boolean, default: false)
      add(:processed_for_discord_at, :utc_datetime)
      add(:processed_for_email, :boolean, default: false)
      add(:processed_for_email_at, :utc_datetime)

      timestamps()
    end
  end
end
