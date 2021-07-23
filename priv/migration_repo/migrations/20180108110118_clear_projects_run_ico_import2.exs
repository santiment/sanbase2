defmodule Sanbase.Repo.Migrations.ClearProjectsRunIcoImport2 do
  use Ecto.Migration

  require Logger

  import Supervisor.Spec

  def up do
    # Making the migration no-op. The data migration is rerun in 20180108140221_clear_projects_run_ico_import3.exs

    # faktory_host = System.get_env("FAKTORY_HOST")
    #
    # if !is_nil(faktory_host) do
    #   opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]
    #   Faktory.Configuration.init
    #   Supervisor.start_link([supervisor(Faktory.Supervisor, [])], opts)
    #
    #   SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport.perform_async([])
    # else
    #   Logger.warn("FAKTORY_HOST variable missing. Skipping ICO import.")
    # end
  end

  def down do
  end
end
