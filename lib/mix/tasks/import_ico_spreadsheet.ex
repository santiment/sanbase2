defmodule Mix.Tasks.ImportIcoSpreadsheet do
  use Mix.Task

  @shortdoc "Imports Ico Spreadsheet"

  @moduledoc """
  Imports Ico Spreadsheet. Imports only the last occurence of a project (matches by project name)

  `mix ImportIcoSpreadsheet --document-id <document_id> --api-key <api_key> [--dry-run] ["project1" "project2" ...]`

  Arguments:
  * `--document-id`, `-d` - Google spreadsheet document id
  * `--api-key`, `-a` - Google api key
  * `["project1" "project2" ...]` - Project names to import. If missing will import everything
  * `--dry-run` - only fetches the spreadsheet data without importing in the db

  To obtain an api key:
  1. Go to https://console.cloud.google.com/
  2. Create a new project
  3. Enable Google Sheets Api
  4. Create an api key
  """

  alias Sanbase.ExternalServices.IcoSpreadsheet

  def run(args) do
    parsed_args = OptionParser.parse(args,
      strict: [document_id: :string, api_key: :string, dry_run: :boolean],
      aliases: [d: :document_id, a: :api_key])

    {switches, project_names, errors} = parsed_args

    switches
    |> set_defaults()
    |> case do
      [document_id: document_id, api_key: api_key, dry_run: dry_run] ->
        cond do
          Enum.empty?(errors) -> import(document_id, api_key, dry_run, project_names)
          true ->
            IO.puts("Missing or invalid arguments")
        end
      _ -> IO.puts("Missing or invalid arguments")
    end
  end

  defp set_defaults(switches) do
    cond do
      Enum.any?(switches, fn {key, _} -> key == :dry_run end) -> switches
      true -> switches ++ [dry_run: false]
    end
  end

  defp import(document_id, api_key, dry_run, project_names) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    data = IcoSpreadsheet.get_project_data(document_id, api_key, project_names)
    |> Enum.reverse()
    |> Enum.uniq_by(fn row -> row.project_name end)
    |> Enum.reverse()

    if !dry_run do
      Sanbase.DbScripts.ImportIcoSpreadsheet.import(data)
    end
  end
end
