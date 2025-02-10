defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  def up do
    "project_long_desc.csv"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> NimbleCSV.RFC4180.parse_string()
    |> Enum.map(fn line ->
      [_, _, _, _, slug, long_desc] = Enum.map(line, &String.trim/1)

      Project
      |> where([p], p.coinmarketcap_id == ^slug)
      |> Repo.update_all(set: [long_description: long_desc])
    end)
  end

  def down, do: :ok
end
