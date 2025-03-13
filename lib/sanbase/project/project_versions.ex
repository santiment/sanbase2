defmodule Sanbase.Project.ProjectVersions do
  @moduledoc """
  Module for querying versions of projects, focusing on creation and hiding events.
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Version
  alias Sanbase.Project
  alias ExAudit.Type.Action

  @doc """
  Get changelog entries grouped by date.
  Returns a list of maps with date, created_projects, and hidden_projects.
  Supports pagination.
  """
  @spec get_changelog_by_date(integer(), integer(), String.t() | nil) ::
          {:ok, list(map())} | {:error, String.t()}
  def get_changelog_by_date(page, page_size, search_term \\ nil) do
    {creation_events_query, hiding_events_query} = build_base_queries()

    {creation_events_query, hiding_events_query} =
      apply_search_filter(creation_events_query, hiding_events_query, search_term)

    creation_events = Repo.all(creation_events_query)
    all_hiding_events = Repo.all(hiding_events_query)
    hiding_events = Enum.filter(all_hiding_events, &is_hiding_event?/1)

    all_events = creation_events ++ hiding_events
    events_by_date = group_events_by_date(all_events)

    sorted_dates = get_sorted_dates(events_by_date)
    total_dates = length(sorted_dates)
    paginated_dates = paginate_dates(sorted_dates, page, page_size)

    projects_by_id = fetch_projects_for_dates(paginated_dates, events_by_date)
    changelog_entries = build_changelog_entries(paginated_dates, events_by_date, projects_by_id)

    {changelog_entries, total_dates}
  end

  defp build_base_queries do
    creation_events_query =
      from(v in Version,
        where: v.entity_schema == ^Sanbase.Project and v.action == :created,
        order_by: [desc: v.recorded_at],
        preload: [:user]
      )

    hiding_events_query =
      from(v in Version,
        where: v.entity_schema == ^Sanbase.Project and v.action == :updated,
        order_by: [desc: v.recorded_at],
        preload: [:user]
      )

    {creation_events_query, hiding_events_query}
  end

  defp apply_search_filter(creation_events_query, hiding_events_query, search_term) do
    if search_term && search_term != "" do
      search_term = "%#{search_term}%"

      creation_events_query =
        from(v in creation_events_query,
          join: p in Project,
          on: v.entity_id == p.id,
          where: ilike(p.name, ^search_term) or ilike(p.ticker, ^search_term)
        )

      hiding_events_query =
        from(v in hiding_events_query,
          join: p in Project,
          on: v.entity_id == p.id,
          where: ilike(p.name, ^search_term) or ilike(p.ticker, ^search_term)
        )

      {creation_events_query, hiding_events_query}
    else
      {creation_events_query, hiding_events_query}
    end
  end

  defp group_events_by_date(events) do
    Enum.group_by(events, fn event -> Date.to_string(event.recorded_at) end)
  end

  defp get_sorted_dates(events_by_date) do
    events_by_date
    |> Map.keys()
    |> Enum.sort(:desc)
  end

  defp paginate_dates(sorted_dates, page, page_size) do
    sorted_dates
    |> Enum.slice(((page - 1) * page_size)..(page * page_size - 1))
    |> Enum.filter(&(&1 != nil))
  end

  defp fetch_projects_for_dates(dates, events_by_date) do
    project_ids =
      dates
      |> Enum.flat_map(fn date ->
        date_events = Map.get(events_by_date, date, [])
        Enum.map(date_events, & &1.entity_id)
      end)
      |> Enum.uniq()

    from(p in Project, where: p.id in ^project_ids)
    |> Repo.all()
    |> Enum.reduce(%{}, fn project, acc -> Map.put(acc, project.id, project) end)
  end

  defp build_changelog_entries(dates, events_by_date, projects_by_id) do
    Enum.map(dates, fn date ->
      date_events = Map.get(events_by_date, date, [])

      {creations, hidings} =
        Enum.split_with(date_events, fn event -> event.action == :created end)

      created_projects = build_created_projects(creations, projects_by_id)
      hidden_projects = build_hidden_projects(hidings, projects_by_id)

      %{
        date: date,
        created_projects: created_projects,
        hidden_projects: hidden_projects
      }
    end)
  end

  defp build_created_projects(creation_events, projects_by_id) do
    Enum.map(creation_events, fn event ->
      project = Map.get(projects_by_id, event.entity_id)

      %{
        project: project,
        event: event
      }
    end)
  end

  defp build_hidden_projects(hiding_events, projects_by_id) do
    Enum.map(hiding_events, fn event ->
      project = Map.get(projects_by_id, event.entity_id)

      %{
        project: project,
        event: event,
        reason: get_hiding_reason(event)
      }
    end)
  end

  def is_hiding_event?(version) do
    patch = version.patch

    case patch do
      %{is_hidden: {:changed, {:primitive_change, false, true}}} ->
        true

      _ ->
        false
    end
  end

  def get_hiding_reason(version) do
    case version.patch do
      %{hidden_reason: {:changed, {:primitive_change, _, reason}}} ->
        reason

      _ ->
        nil
    end
  end
end
