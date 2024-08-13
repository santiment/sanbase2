defmodule Sanbase.Repo.Migrations.ImportProjectDescriptions do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Project

  def up do
    Path.expand("cmc_name_list.csv", __DIR__)
    |> File.read!()
    |> NimbleCSV.RFC4180.parse_string()
    |> Enum.each(fn description_line ->
      [project, description] =
        description_line
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&empty_description?/1)

      [_name, ticker] = String.split(project, ";")

      Project
      |> where([p], p.ticker == ^ticker)
      |> Repo.update_all(set: [description: description])
    end)
  end

  defp empty_description?("-"), do: true
  defp empty_description?(""), do: true

  defp empty_description?(description), do: false
end
