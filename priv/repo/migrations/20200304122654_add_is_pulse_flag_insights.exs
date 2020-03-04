defmodule Sanbase.Repo.Migrations.AddIsPulseFlagInsights do
  use Ecto.Migration

  # Add `is_pulse`
  def change do
    alter table("posts") do
      add(:is_pulse, :boolean, default: false)
    end
  end
end
