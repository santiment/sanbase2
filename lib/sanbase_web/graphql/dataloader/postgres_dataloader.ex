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

  def query(:comment_insight_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.post_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comments_count, post_ids) do
    ids = Enum.to_list(post_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.post_id in ^ids,
      group_by: mapping.post_id,
      select: {mapping.post_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end
end
