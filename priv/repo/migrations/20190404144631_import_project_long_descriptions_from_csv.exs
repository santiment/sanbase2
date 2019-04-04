defmodule Sanbase.Repo.Migrations.ImportProjectLongDescriptionsFromCSV do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def up() do
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    Path.expand("project_long_desc.csv", __DIR__)
    |> File.stream!()
    |> CSV.decode()
    |> Stream.drop(1)
    |> Enum.map(fn {:ok, line} ->
      [_, _, _, _, slug, long_desc] = line |> Enum.map(&String.trim/1)

      Project
      |> where([p], p.coinmarketcap_id == ^slug)
      |> Repo.update_all(set: [long_description: long_desc])
    end)
  end

  def down(), do: :ok
end
