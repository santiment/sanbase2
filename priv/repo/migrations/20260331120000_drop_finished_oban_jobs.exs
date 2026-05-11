defmodule Sanbase.Repo.Migrations.DropFinishedObanJobs do
  use Ecto.Migration

  def up do
    drop_if_exists(table(:finished_oban_jobs))

    execute("DROP FUNCTION IF EXISTS movefinishedobanjobs(character varying, bigint)")
  end

  def down do
    :ok
  end
end
