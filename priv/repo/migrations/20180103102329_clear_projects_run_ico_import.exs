defmodule Sanbase.Repo.Migrations.ClearProjectsRunIcoImport do
  use Ecto.Migration

  require Logger

  import Supervisor.Spec

  def up do
    document_id = System.get_env("ICO_IMPORT_DOCUMENT_ID")
    api_key = System.get_env("ICO_IMPORT_API_KEY")

    if !is_nil(document_id) and !is_nil(api_key) do
      opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]
      Faktory.Configuration.init
      Supervisor.start_link([supervisor(Faktory.Supervisor, [])], opts)

      SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport.perform_async([document_id, api_key])
    else
      Logger.warn("ICO_IMPORT_DOCUMENT_ID or ICO_IMPORT_API_KEY variable missing. Skipping ICO import.")
    end
  end

  def down do
  end
end
