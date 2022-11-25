defmodule Sanbase.Repo.Migrations.AddCryptocompareSourceSlugMapping do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project

  def up do
    setup()

    mapping =
      Path.join(__DIR__, "santiment_cryptocompare_slug_mapping.json")
      |> File.read!()
      |> Jason.decode!()

    projects_map = Project.List.projects(include_hidden: true) |> Map.new(&{&1.slug, &1})

    data =
      mapping
      |> Enum.filter(&Map.has_key?(projects_map, &1["san_slug"]))
      |> Enum.map(fn elem ->
        %{
          slug: elem["cpc_symbol"],
          source: "cryptocompare",
          project_id: Map.get(projects_map, elem["san_slug"]) |> Map.get(:id)
        }
      end)

    Sanbase.Repo.insert_all(Project.SourceSlugMapping, data)
  end

  def down do
    from(ssm in Project.SourceSlugMapping, where: ssm.source == "cryptocompare")
    |> Sanbase.Repo.delete_all()
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
