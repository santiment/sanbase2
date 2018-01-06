defmodule SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport2 do
  use Faktory.Job

  alias Sanbase.ExternalServices.IcoSpreadsheet

  import Ecto.Query, warn: false

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico

  faktory_options queue: "data_migrations", retry: 25, priority: 9

  def perform() do
    document_id = System.get_env("ICO_IMPORT_DOCUMENT_ID")
    api_key = System.get_env("ICO_IMPORT_API_KEY")

    if !is_nil(document_id) and !is_nil(api_key) do
      ico_spreadsheet = IcoSpreadsheet.get_project_data(document_id, api_key, [])
      Repo.transaction(fn ->
        clear_data()

        Sanbase.DbScripts.ImportIcoSpreadsheet.import(ico_spreadsheet)
      end)
    else
      raise "ICO_IMPORT_DOCUMENT_ID or ICO_IMPORT_API_KEY variable missing. Cannot do ICO import."
    end
  end

  defp clear_data do
    from(p in Project,
    where: like(fragment("lower(?)", p.name), "% (presale)"))
    |> Repo.delete_all

    Repo.delete_all(Ico)
  end
end
