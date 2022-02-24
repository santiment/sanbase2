defmodule Sanbase.Repo.Migrations.RemoveObanJobs do
  use Ecto.Migration

  def up do
    Oban.Migrations.down(version: 1)
  end

  def down do
    Oban.Migrations.up()
  end
end
