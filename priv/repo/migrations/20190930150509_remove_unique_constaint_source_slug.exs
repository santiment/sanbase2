defmodule Sanbase.Repo.Migrations.RemoveUniqueConstaintSourceSlug do
  @moduledoc false
  use Ecto.Migration

  @table "source_slug_mappings"

  def up do
    drop(unique_index(@table, [:source, :slug], name: :source_slug_unique_combination))
  end

  def down do
    create(unique_index(@table, [:source, :slug], name: :source_slug_unique_combination))
  end
end
