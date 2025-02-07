defmodule Sanbase.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:status, :string, null: false, default: "regular")
    end
  end
end
