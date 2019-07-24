defmodule Sanbase.Repo.Migrations.AddComputedAtToExchangeAddresses do
  use Ecto.Migration

  def change do
    alter table("exchange_addresses") do
      add(:computed_at, :naive_datetime)
    end
  end
end
