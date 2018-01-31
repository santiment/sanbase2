defmodule Sanbase.Repo.Migrations.AddValuesToIcoCurrencies do
  use Ecto.Migration

  def change do
    alter table(:ico_currencies) do
      add(:value, :decimal)
    end
  end
end
