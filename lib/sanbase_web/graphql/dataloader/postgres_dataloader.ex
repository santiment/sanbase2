defmodule SanbaseWeb.Graphql.MetricPostgresDataloader do
  import Ecto.Query
  alias Sanbase.Model.{MarketSegment, Infrastructure}
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

  def query(:comment_insight_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.post_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_timeline_event_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.Timeline.TimelineEventComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.timeline_event_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_short_url_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.ShortUrl.ShortUrlComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.short_url_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:insights_comments_count, post_ids) do
    ids = Enum.to_list(post_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.post_id in ^ids,
      group_by: mapping.post_id,
      select: {mapping.post_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:insights_count_per_user, _user_ids) do
    {:ok, map} = Sanbase.Insight.Post.insights_count_map()
    map
  end

  def query(:timeline_events_comments_count, timeline_events_ids) do
    ids = Enum.to_list(timeline_events_ids)

    from(mapping in Sanbase.Timeline.TimelineEventComment,
      where: mapping.timeline_event_id in ^ids,
      group_by: mapping.timeline_event_id,
      select: {mapping.timeline_event_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:short_urls_comments_count, short_url_ids) do
    ids = Enum.to_list(short_url_ids)

    from(mapping in Sanbase.ShortUrl.ShortUrlComment,
      where: mapping.short_url_id in ^ids,
      group_by: mapping.short_url_id,
      select: {mapping.short_url_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:project_by_slug, slugs) do
    slugs
    |> Enum.to_list()
    |> Sanbase.Model.Project.List.by_slugs()
    |> Enum.into(%{}, fn %{slug: slug} = project -> {slug, project} end)
  end
end
