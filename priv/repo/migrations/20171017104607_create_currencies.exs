defmodule Sanbase.Repo.Migrations.CreateCurrencies do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:currencies) do
      add(:code, :string, null: false)
    end

    create(unique_index(:currencies, [:code]))
  end
end
