defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV2 do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def up() do
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    result =
      Path.expand("project_long_desc.csv", __DIR__)
      |> File.stream!()
      |> CSV.decode()
      |> Stream.drop(1)
      |> Enum.map(fn {:ok, line} ->
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

    result |> Enum.filter(fn x -> is_number(x) end) |> Enum.sum() |> IO.inspect(label: "success")
    result |> Enum.filter(fn x -> is_binary(x) end) |> IO.inspect(label: "not success")
  end

  def down(), do: :ok
end
