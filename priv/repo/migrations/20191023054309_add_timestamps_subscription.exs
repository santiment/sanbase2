defmodule Sanbase.Repo.Migrations.AddTimestampsSubscription do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      timestamps(null: true)
    end
  end
end
