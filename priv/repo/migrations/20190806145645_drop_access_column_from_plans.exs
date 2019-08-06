defmodule Sanbase.Repo.Migrations.DropAccessColumnFromPlans do
  use Ecto.Migration

  def change do
    alter table("plans") do
      remove(:access)
    end
  end
end
