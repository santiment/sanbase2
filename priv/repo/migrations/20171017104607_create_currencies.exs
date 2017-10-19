defmodule Sanbase.Repo.Migrations.CreateCurrencies do
  use Ecto.Migration

  def change do
    create table(:currencies) do
      add :code, :text, unique: true
    end

  end
end
