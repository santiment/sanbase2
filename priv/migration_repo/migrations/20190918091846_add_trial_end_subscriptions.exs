defmodule Sanbase.Repo.Migrations.AddTrialEndSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add(:trial_end, :utc_datetime, null: true)
    end
  end
end
