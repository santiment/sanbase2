defmodule Sanbase.Project.Jobs do
  @moduledoc false
  alias Sanbase.Project

  require Logger

  def fill_coinmarketcap_id do
    Logger.info("Run Sanbase.Project.Jobs fill_coinmarketcap_id job")

    projects = Project.List.projects()

    coinmarketcap_mapping =
      "coinmarketcap"
      |> Project.SourceSlugMapping.get_source_slug_mappings()
      |> Map.new(fn {source, san} -> {san, source} end)

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
