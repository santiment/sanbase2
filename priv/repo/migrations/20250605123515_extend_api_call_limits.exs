defmodule Sanbase.Repo.Migrations.ExtendApiCallLimits do
  use Ecto.Migration

  def change do
    alter table(:api_call_limits) do
      add(:api_calls_responses_size_mb, :map, default: %{})
      add(:api_calls_limit_subscription_status, :string, default: "active")
    end
  end
end
