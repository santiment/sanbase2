defmodule SanbaseWeb.Graphql.MetricPostgresDataloader do
  import Ecto.Query
  alias Sanbase.Model.Project.SocialVolumeQuery
  alias Sanbase.Model.{MarketSegment, Infrastructure, Project}
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

  def query(:comment_blockchain_address_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.BlockchainAddress.BlockchainAddressComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.blockchain_address_id}
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

  def query(:blockchain_addresses_comments_count, blockchain_address_ids) do
    ids = Enum.to_list(blockchain_address_ids)

    from(mapping in Sanbase.BlockchainAddress.BlockchainAddressComment,
      where: mapping.blockchain_address_id in ^ids,
      group_by: mapping.blockchain_address_id,
      select: {mapping.blockchain_address_id, fragment("COUNT(*)")}
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

  def query(:social_volume_query, projects_ids) do
    all_projects = Project.List.projects(preload: [:social_volume_query])

    current_projects = Enum.filter(all_projects, &(&1.id in projects_ids))

    Map.new(
      current_projects,
      fn
        %{social_volume_query: %{query: query}} = project when not is_nil(query) ->
          {project.id, query}

        %Project{} = project ->
          exclusion_string =
            all_projects
            |> filter_similar_projects(project)
            |> Enum.map(fn excluded_project -> "NOT \"#{excluded_project.name}\"" end)
            |> Enum.join(" ")

          query = SocialVolumeQuery.default_query(project)

          generate_social_query(project.id, query, exclusion_string)
      end
    )
  end

  defp filter_similar_projects(all_projects, project) do
    %Project{ticker: project_ticker, slug: project_slug, name: project_name} = project

    Enum.filter(all_projects, fn other_project ->
      %Project{name: other_name, slug: other_slug} = other_project
      other_project_names = String.downcase(other_name) |> String.split([" ", "-"])
      downcased_project_name = String.downcase(project_name)

      if project_slug !== other_slug do
        Enum.any?(other_project_names, fn element ->
          element === downcased_project_name || element === project_slug ||
            element === project_ticker
        end)
      end
    end)
  end

  defp generate_social_query(id, query, exclusion_string) do
    if exclusion_string === "" do
      {id, query}
    else
      {id, query <> " " <> exclusion_string}
    end
  end
end
