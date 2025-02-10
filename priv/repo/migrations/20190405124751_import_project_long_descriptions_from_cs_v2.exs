defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV2 do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  def up do
    result =
      "project_long_desc.csv"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> NimbleCSV.RFC4180.parse_string()
      |> Enum.map(fn line ->
        [_, _, _, slug, long_desc] = Enum.map(line, &String.trim/1)

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
    Enum.filter(result, fn x -> is_binary(x) end)
  end

  def down, do: :ok
end
