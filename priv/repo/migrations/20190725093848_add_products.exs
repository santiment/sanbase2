defmodule Sanbase.Repo.Migrations.AddProducts do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO products (id, name) VALUES
      (2, 'SANBase'),
      (3, 'SANsheets'),
      (4, 'SANGraphs')
    """)
  end

  def down do
    execute("DELETE FROM products where id IN (2, 3, 4)")
  end
end
