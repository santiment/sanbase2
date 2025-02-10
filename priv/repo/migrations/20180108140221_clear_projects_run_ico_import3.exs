defmodule Sanbase.Repo.Migrations.ClearProjectsRunIcoImport3 do
  @moduledoc false
  use Ecto.Migration

  import Supervisor.Spec

  require Logger

  def up do
    faktory_host = System.get_env("FAKTORY_HOST")

    if is_nil(faktory_host) do
      Logger.warning("FAKTORY_HOST variable missing. Skipping ICO import.")
    else
      opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]
      Faktory.Configuration.init()
      Supervisor.start_link([supervisor(Faktory.Supervisor, [])], opts)

      SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport.perform_async([])
    end
  end

  def down do
  end
end
