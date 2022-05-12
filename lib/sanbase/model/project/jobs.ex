defmodule Sanbase.Model.Project.Jobs do
  alias Sanbase.Model.Project

  require Logger

  def fill_coinmarketcap_id() do
    Logger.info("Run Sanbase.Model.Project.Jobs fill_coinmarketcap_id job")

    projects = Project.List.projects()

    coinmarketcap_mapping =
      Project.SourceSlugMapping.get_source_slug_mappings("coinmarketcap")
      |> Enum.map(fn {source, san} -> {san, source} end)
      |> Map.new()

    multi =
      Enum.reduce(projects, Ecto.Multi.new(), fn project, multi ->
        case Map.get(coinmarketcap_mapping, project.slug) do
          id when id == project.coinmarketcap_id ->
            multi

          coinmarketcap_id ->
            changeset = Project.changeset(project, %{coinmarketcap_id: coinmarketcap_id})
            Ecto.Multi.update(multi, project.id, changeset)
        end
      end)

    {:ok, _} = Sanbase.Repo.transaction(multi)
  end
end
