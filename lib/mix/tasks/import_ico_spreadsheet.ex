defmodule Mix.Tasks.ImportIcoSpreadsheet do
  use Mix.Task

  @shortdoc "Imports Ico Spreadsheet"

  @moduledoc """
  Imports Ico Spreadsheet. Imports only the last occurence of a project (matches by project name)

  `mix ImportIcoSpreadsheet --document-id <document_id> --api-key <api_key> ["project1" "project2" ...]`

  Arguments:
  * `--document-id`, `-d` - Google spreadsheet document id
  * `--api-key`, `-a` - Google api key
  * `["project1" "project2" ...]` - Project names to import. If missing will import everything

  To obtain an api key:
  1. Go to https://console.cloud.google.com/
  2. Create a new project
  3. Enable Google Sheets Api
  4. Create an api key
  """

  alias Sanbase.ExternalServices.IcoSpreadsheet

  def run(args) do
    parsed_args = OptionParser.parse(args,
      strict: [document_id: :string, api_key: :string],
      aliases: [d: :document_id, a: :api_key])

    case parsed_args do
      {[document_id: document_id, api_key: api_key], project_names, errors} ->
        cond do
          Enum.empty?(errors) -> import(document_id, api_key, project_names)
          true ->
            IO.puts("Missing or invalid arguments")
        end
      _ -> IO.puts("Missing or invalid arguments")
    end
  end

  defp import(document_id, api_key, project_names) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    IcoSpreadsheet.get_project_data(document_id, api_key, project_names)
    |> Enum.reverse()
    |> Enum.uniq_by(fn row -> row.project_name end)
    |> Enum.reverse()
    |> Sanbase.DbScripts.ImportIcoSpreadsheet.import()
  end
end
