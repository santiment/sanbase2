defmodule Sanbase.Repo.Migrations.AddIsPrivateFieldPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:is_private, :boolean, default: false)
    end
  end
end
