defmodule Sanbase.Repo.Migrations.RenameIcoCurrenciesValueToAmount do
  use Ecto.Migration

  def change do
    rename(table(:ico_currencies), :value, to: :amount)
  end
end
