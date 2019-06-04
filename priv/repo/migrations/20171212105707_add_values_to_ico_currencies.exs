defmodule Sanbase.Repo.Migrations.AddValuesToIcoCurrency do
  use Ecto.Migration

  def change do
    alter table(:ico_currencies) do
      add(:value, :decimal)
    end
  end
end
