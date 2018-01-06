defmodule Sanbase.Repo.Migrations.ClearProjectsRunIcoImport2 do
  use Ecto.Migration

  require Logger

  import Supervisor.Spec

  def up do
    if(data_migrations?()) do
      faktory_host = System.get_env("FAKTORY_HOST")

      if !is_nil(faktory_host) do
        opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]
        Faktory.Configuration.init
        Supervisor.start_link([supervisor(Faktory.Supervisor, [])], opts)

        SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport2.perform_async([])
      else
        raise "FAKTORY_HOST variable missing. Cannot schedule ICO import."
      end
    else
      Logger.warn("DATA_MIGRATIONS not set. Skipping ICO import.")
    end
  end

  def down do
  end

  defp data_migrations?() do
    data_migrations = System.get_env("DATA_MIGRATIONS")

    !is_nil(data_migrations)
    and (String.downcase(data_migrations) == "true"
        or String.downcase(data_migrations) == "1")
  end
end
