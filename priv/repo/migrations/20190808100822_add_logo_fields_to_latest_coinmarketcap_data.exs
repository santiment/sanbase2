defmodule Sanbase.Repo.Migrations.AddLogoFieldsToLatestCoinmarketcapData do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add(:logo_hash, :string)
      add(:logo_updated_at, :naive_datetime)
    end
  end
end
