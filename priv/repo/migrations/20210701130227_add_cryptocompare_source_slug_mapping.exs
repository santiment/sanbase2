defmodule Sanbase.Repo.Migrations.AddCryptocompareSourceSlugMapping do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project

  def up do
    setup()

    mapping =
      __DIR__
      |> Path.join("santiment_cryptocompare_slug_mapping.json")
      |> File.read!()
      |> Jason.decode!()

    projects_map = [include_hidden: true] |> Project.List.projects() |> Map.new(&{&1.slug, &1})

    data =
      mapping
      |> Enum.filter(&Map.has_key?(projects_map, &1["san_slug"]))
      |> Enum.map(fn elem ->
        %{
          slug: elem["cpc_symbol"],
          source: "cryptocompare",
          project_id: projects_map |> Map.get(elem["san_slug"]) |> Map.get(:id)
        }
      end)

    Sanbase.Repo.insert_all(Project.SourceSlugMapping, data)
  end

  def down do
    Sanbase.Repo.delete_all(from(ssm in Project.SourceSlugMapping, where: ssm.source == "cryptocompare"))
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
