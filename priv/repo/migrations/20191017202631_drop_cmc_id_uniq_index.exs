defmodule Sanbase.Repo.Migrations.DropCmcIdUniqIndex do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(unique_index("project", [:coinmarketcap_id]))
  end

  def down do
    create(unique_index("project", [:coinmarketcap_id]))
  end
end
