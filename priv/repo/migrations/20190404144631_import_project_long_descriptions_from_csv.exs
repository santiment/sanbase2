defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Project

  def up() do
    Path.expand("project_long_desc.csv", __DIR__)
    |> File.read!()
    |> NimbleCSV.RFC4180.parse_string()
    |> Enum.map(fn line ->
      [_, _, _, _, slug, long_desc] = line |> Enum.map(&String.trim/1)

      Project
      |> where([p], p.coinmarketcap_id == ^slug)
      |> Repo.update_all(set: [long_description: long_desc])
    end)
  end

  def down(), do: :ok
end
