defmodule Sanbase.Repo.Migrations.RemoveUpdateTimeNotNull do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      modify(:update_time, :naive_datetime, null: true)
    end
  end
end
