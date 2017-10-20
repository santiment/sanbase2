defmodule Sanbase.Repo.Migrations.CreateIcoCurrencies do
  use Ecto.Migration

  def change do
    create table(:ico_currencies) do
      add :ico_id, references(:icos), null: false
      add :currency_id, references(:currencies), null: false
    end

    create index(:ico_currencies, [:ico_id])
    create index(:ico_currencies, [:currency_id])
  end
end
