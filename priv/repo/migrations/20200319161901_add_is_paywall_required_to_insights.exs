defmodule Sanbase.Repo.Migrations.AddIsPaywallRequiredToInsights do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("posts") do
      add(:is_paywall_required, :boolean, default: false)
    end
  end
end
