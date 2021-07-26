defmodule Sanbase.Repo.Migrations.AddIsRegisteredFieldToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:is_registered, :boolean, default: false)
    end
  end
end
