defmodule Mix.Tasks.ImportIcoSpreadsheet do
  use Mix.Task

  @shortdoc "Imports Ico Spreadsheet"

  alias Sanbase.ExternalServices.IcoSpreadsheet

  def run(project_names) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    res = IcoSpreadsheet.get_project_data!(project_names)

    IO.inspect res
  end
end
