defmodule Sanbase.Repo.Migrations.AddCodeToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add(:code, :string)
    end

    create(unique_index(:products, [:code]))
  end
end
