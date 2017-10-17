defmodule Sanbase.Repo.Migrations.CreateIcoCurrencies do
  use Ecto.Migration

  def change do
    create table(:ico_currencies, primary_key: false) do
      add :ico_id, references(:icos, on_delete: :nothing), null: false
      add :currency_code, references(:currencies, type: :text, column: :code, on_delete: :nothing), null: false
    end

    create index(:ico_currencies, [:ico_id])
    create index(:ico_currencies, [:currency_code])
  end
end
