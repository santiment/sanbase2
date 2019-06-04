defmodule Sanbase.Repo.Migrations.RenameIcoCurrencyValueToAmount do
  use Ecto.Migration

  def change do
    rename(table(:ico_currencies), :value, to: :amount)
  end
end
