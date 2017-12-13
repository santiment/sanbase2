defmodule Sanbase.Repo.Migrations.AddIcoCurrenciesUk do
  use Ecto.Migration

  def up do
    create unique_index(:ico_currencies, [:ico_id, :currency_id], name: :ico_currencies_uk)
  end

  def down do
    drop unique_index(:ico_currencies, [:ico_id, :currency_id], name: :ico_currencies_uk)
  end
end
