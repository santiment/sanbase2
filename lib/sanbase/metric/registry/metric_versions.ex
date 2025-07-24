defmodule Sanbase.Metric.Registry.MetricVersions do
  @moduledoc """
  Module for querying versions of metrics, focusing on creation and deprecation events.
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Version
  alias Sanbase.Metric.Registry, as: MetricRegistry

  @doc """
  Get changelog entries grouped by date with infinite scrolling pagination.
  Returns a list of maps with date, created_metrics, and deprecated_metrics.
  Supports limit and offset for infinite scrolling.
  """
  @spec get_changelog_by_date(integer(), integer(), String.t() | nil) ::
          {list(map()), boolean(), integer()}
  def get_changelog_by_date(limit, offset, search_term \\ nil) do
    {creation_events_query, deprecation_events_query} = build_base_queries()

    {creation_events_query, deprecation_events_query} =
      apply_search_filter(creation_events_query, deprecation_events_query, search_term)

    creation_events = creation_events_query |> Repo.all()
    all_deprecation_events = deprecation_events_query |> Repo.all()
    deprecation_events = Enum.filter(all_deprecation_events, &is_deprecation_event?/1)

    all_events = creation_events ++ deprecation_events
    events_by_date = group_events_by_date(all_events)

    # Get all dates sorted in descending order
    sorted_dates = get_sorted_dates(events_by_date)
    total_dates = length(sorted_dates)

    # Get a slice of dates for the current page (infinite scrolling)
    paginated_dates = paginate_dates(sorted_dates, limit, offset)

    # Check if there are more dates to load
    has_more = total_dates > offset + length(paginated_dates)

    metrics_by_id = fetch_metrics_for_dates(paginated_dates, events_by_date)
    changelog_entries = build_changelog_entries(paginated_dates, events_by_date, metrics_by_id)

    {changelog_entries, has_more, total_dates}
  end

  defp build_base_queries do
    # Use the atom for entity schema, exactly like the project_versions module
    creation_events_query =
      from(v in Version,
        where: v.entity_schema == ^Sanbase.Metric.Registry and v.action == :created,
        order_by: [desc: v.recorded_at],
        preload: [:user]
      )

    deprecation_events_query =
      from(v in Version,
        where: v.entity_schema == ^Sanbase.Metric.Registry and v.action == :updated,
        order_by: [desc: v.recorded_at],
        preload: [:user]
      )

    {creation_events_query, deprecation_events_query}
  end

  defp apply_search_filter(creation_events_query, deprecation_events_query, search_term) do
    if search_term && search_term != "" do
      search_term = "%#{search_term}%"

      creation_events_query =
        from(v in creation_events_query,
          join: m in MetricRegistry,
          on: v.entity_id == m.id,
          where: ilike(m.metric, ^search_term) or ilike(m.human_readable_name, ^search_term)
        )

      deprecation_events_query =
        from(v in deprecation_events_query,
          join: m in MetricRegistry,
          on: v.entity_id == m.id,
          where: ilike(m.metric, ^search_term) or ilike(m.human_readable_name, ^search_term)
        )

      {creation_events_query, deprecation_events_query}
    else
      {creation_events_query, deprecation_events_query}
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

  defp paginate_dates(sorted_dates, limit, offset) do
    sorted_dates
    |> Enum.slice(offset..(offset + limit - 1))
    |> Enum.filter(&(&1 != nil))
  end

  defp fetch_metrics_for_dates(dates, events_by_date) do
    metric_ids =
      dates
      |> Enum.flat_map(fn date ->
        date_events = Map.get(events_by_date, date, [])
        Enum.map(date_events, & &1.entity_id)
      end)
      |> Enum.uniq()

    from(m in MetricRegistry, where: m.id in ^metric_ids)
    |> Repo.all()
    |> Enum.reduce(%{}, fn metric, acc -> Map.put(acc, metric.id, metric) end)
  end

  defp build_changelog_entries(dates, events_by_date, metrics_by_id) do
    Enum.map(dates, fn date ->
      date_events = Map.get(events_by_date, date, [])

      {creations, deprecations} =
        Enum.split_with(date_events, fn event -> event.action == :created end)

      created_metrics = build_created_metrics(creations, metrics_by_id)
      deprecated_metrics = build_deprecated_metrics(deprecations, metrics_by_id)

      %{
        date: date,
        created_metrics: created_metrics,
        deprecated_metrics: deprecated_metrics
      }
    end)
  end

  defp build_created_metrics(creation_events, metrics_by_id) do
    Enum.map(creation_events, fn event ->
      metric = Map.get(metrics_by_id, event.entity_id)

      %{
        metric: metric,
        event: event
      }
    end)
  end

  defp build_deprecated_metrics(deprecation_events, metrics_by_id) do
    Enum.map(deprecation_events, fn event ->
      metric = Map.get(metrics_by_id, event.entity_id)

      %{
        metric: metric,
        event: event,
        note: get_deprecation_note(event)
      }
    end)
  end

  def is_deprecation_event?(version) do
    patch = version.patch

    case patch do
      %{is_deprecated: {:changed, {:primitive_change, false, true}}} ->
        true

      _ ->
        false
    end
  end

  def get_deprecation_note(version) do
    case version.patch do
      %{deprecation_note: {:changed, {:primitive_change, _, note}}} ->
        note

      _ ->
        nil
    end
  end
end
