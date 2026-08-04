defmodule Sanbase.Repo.Migrations.AddResolvedApiCallLimitsToApiCallLimits do
  @moduledoc ~s"""
  Where a bundle customer's call limits live.

  Every other plan's limits are derived from its name, which works because the
  name identifies the numbers. Every bundle is named `BUNDLE` while the numbers
  differ per customer, so they are resolved when the subscription syncs and stored
  here.

  Nullable, and null for every existing row: a null means "derive from the plan
  name", which is what happens today. No backfill, and no behavior change for
  anyone who is not on a bundle.
  """

  use Ecto.Migration

  def change do
    alter table(:api_call_limits) do
      add(:resolved_api_call_limits, :jsonb, null: true)
    end
  end
end
