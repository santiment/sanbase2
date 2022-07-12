defmodule Sanbase.Repo.Migrations.AddManualHasApiCallLimitsField do
  use Ecto.Migration

  def change do
    alter table(:api_call_limits) do
      add(:has_limits_no_matter_plan, :boolean, default: true)
    end
  end
end
