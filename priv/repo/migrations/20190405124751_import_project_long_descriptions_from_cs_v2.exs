defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV2 do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Project

  def up() do
    result =
      Path.expand("project_long_desc.csv", __DIR__)
      |> File.read!()
      |> NimbleCSV.RFC4180.parse_string()
      |> Enum.map(fn line ->
        [_, _, _, slug, long_desc] = line |> Enum.map(&String.trim/1)

        {rows, _} =
          Project
          |> where([p], p.coinmarketcap_id == ^slug)
          |> Repo.update_all(set: [long_description: long_desc])

        if rows > 0 do
          rows
        else
          slug
        end
      end)

    result |> Enum.filter(fn x -> is_number(x) end) |> Enum.sum()
    result |> Enum.filter(fn x -> is_binary(x) end)
  end

  def down(), do: :ok
end
