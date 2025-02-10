defmodule Sanbase.Repo.Migrations.AddApiCallLimitsTable do
  @moduledoc false
  use Ecto.Migration

  @table :api_call_limits
  def change do
    create table(@table) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:remote_ip, :string, default: nil)
      add(:has_limits, :boolean, default: true)
      add(:api_calls_limit_plan, :string, default: "free")
      add(:api_calls, :map, default: %{})
    end

    create(unique_index(@table, [:user_id]))
    create(unique_index(@table, [:remote_ip]))
  end
end
