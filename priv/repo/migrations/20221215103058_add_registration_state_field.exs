defmodule Sanbase.Repo.Migrations.AddRegistrationStateField do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:registration_state, :jsonb, default: ~s({"state": "init"}))
    end
  end
end
