defmodule Sanbase.Repo.Migrations.CreateProductsTable do
  use Ecto.Migration

  def up do
    create table(:products) do
      add(:name, :string)
      add(:stripe_id, :string)
    end

    execute("""
    INSERT INTO products (id, name) VALUES
      (1, 'SANapi')
    """)
  end

  def down do
    drop(table(:products))
  end
end
