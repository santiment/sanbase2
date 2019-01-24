defmodule SanbaseWeb.Graphql.PostgresDataloader do
  import Ecto.Query
  alias Sanbase.Model.{MarketSegment, Infrastructure, ProjectTransparencyStatus}
  alias Sanbase.Repo

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:market_segment, market_segment_ids) do
    market_segment_ids = Enum.to_list(market_segment_ids)

    from(ms in MarketSegment,
      where: ms.id in ^market_segment_ids
    )
    |> Repo.all()
    |> Enum.map(fn %MarketSegment{id: id, name: name} -> {id, name} end)
    |> Map.new()
  end

  def query(:infrastructure, infrastructure_ids) do
    infrastructure_ids = Enum.to_list(infrastructure_ids)

    from(inf in Infrastructure,
      where: inf.id in ^infrastructure_ids
    )
    |> Repo.all()
    |> Enum.map(fn %Infrastructure{id: id, code: code} -> {id, code} end)
    |> Map.new()
  end

  def query(:project_transparency_status, project_transparency_status_ids) do
    project_transparency_status_ids = Enum.to_list(project_transparency_status_ids)

    from(pts in ProjectTransparencyStatus, where: pts.id in ^project_transparency_status_ids)
    |> Repo.all()
    |> Enum.map(fn %ProjectTransparencyStatus{id: id, name: name} -> {id, name} end)
    |> Map.new()
  end
end
