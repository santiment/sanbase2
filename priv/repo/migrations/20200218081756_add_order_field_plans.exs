defmodule Sanbase.Repo.Migrations.AddOrderFieldPlans do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:order, :integer, default: 0)
    end
  end
end
