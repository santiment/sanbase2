defmodule Sanbase.Repo.Migrations.AddStripeEventsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:stripe_events, primary_key: false) do
      add(:event_id, :string, primary_key: true)
      add(:type, :string, null: false)
      add(:payload, :jsonb, null: false)
      add(:is_processed, :boolean, default: false)

      timestamps
    end
  end
end
