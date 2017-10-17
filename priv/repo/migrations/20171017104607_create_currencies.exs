defmodule Sanbase.Repo.Migrations.CreateCurrencies do
  use Ecto.Migration

  def change do
    create table(:currencies, primary_key: false) do
      add :code, :text, primary_key: true
    end

  end
end
