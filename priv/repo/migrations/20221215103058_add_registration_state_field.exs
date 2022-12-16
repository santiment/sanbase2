defmodule Sanbase.Repo.Migrations.AddRegistrationStateField do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:registration_state, :jsonb, default: "{\"state\": \"init\"}")
    end
  end
end
