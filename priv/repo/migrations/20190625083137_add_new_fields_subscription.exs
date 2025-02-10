defmodule Sanbase.Repo.Migrations.AddNewFieldsSubscription do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add(:cancel_at_period_end, :boolean, null: false, default: false)
      add(:current_period_end, :utc_datetime)
    end
  end
end
