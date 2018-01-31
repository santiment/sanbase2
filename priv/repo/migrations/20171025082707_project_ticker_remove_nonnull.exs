defmodule Sanbase.Repo.Migrations.ProjectTickerRemoveNonnull do
  use Ecto.Migration

  def up do
    alter table("project") do
      modify(:ticker, :string, null: true)
    end
  end

  def down do
    alter table("project") do
      modify(:ticker, :string, null: false)
    end
  end
end
