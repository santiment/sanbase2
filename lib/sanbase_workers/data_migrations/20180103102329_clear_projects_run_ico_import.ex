defmodule SanbaseWorkers.DataMigrations.ClearProjectsRunIcoImport do
  use Faktory.Job

  alias Sanbase.ExternalServices.IcoSpreadsheet

  import Ecto.Query, warn: false

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico

  faktory_options queue: "data_migrations", retry: 1

  def perform(document_id, api_key) do
    clear_data()

    IcoSpreadsheet.get_project_data(document_id, api_key, [])
    |> Sanbase.DbScripts.ImportIcoSpreadsheet.import()
  end

  defp clear_data do
    from(p in Project,
    where: like(fragment("lower(?)", p.name), "% (presale)"))
    |> Repo.delete_all

    Repo.delete_all(Ico)
  end
end
