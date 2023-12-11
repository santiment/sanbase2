defmodule Sanbase.Repo.Migrations.AddIsPppPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:is_ppp, :boolean, default: false)
    end
  end
end
