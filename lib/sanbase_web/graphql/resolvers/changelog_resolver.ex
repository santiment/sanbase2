defmodule SanbaseWeb.Graphql.Resolvers.ChangelogResolver do
  @moduledoc """
  Resolvers for changelog-related GraphQL queries.
  """

  alias Sanbase.Metric.Registry.MetricVersions
  alias Sanbase.Project.ProjectVersions
  alias Sanbase.Project

  @default_page_size 20

  @doc """
  Get metrics changelog with pagination support.
  Supports both infinite scroll and traditional pagination using page/pageSize.
  """
  def metrics_changelog(_root, args, _resolution) do
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, @default_page_size)
    search_term = Map.get(args, :search_term)

    # Convert page/pageSize to limit/offset for the existing function
    limit = page_size
    offset = (page - 1) * page_size

    case MetricVersions.get_changelog_by_date(limit, offset, search_term) do
      {changelog_entries, has_more, total_dates} ->
        entries = format_metrics_changelog_entries(changelog_entries)
        total_pages = calculate_total_pages(total_dates, page_size)

        pagination = %{
          has_more: has_more,
          total_dates: total_dates,
          current_page: page,
          total_pages: total_pages
        }

        result = %{
          entries: entries,
          pagination: pagination
        }

        {:ok, result}

      error ->
        {:error, "Failed to fetch metrics changelog: #{inspect(error)}"}
    end
  end

  @doc """
  Get assets (projects) changelog with pagination support.
  """
  def assets_changelog(_root, args, _resolution) do
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, @default_page_size)
    search_term = Map.get(args, :search_term)

    case ProjectVersions.get_changelog_by_date(page, page_size, search_term) do
      {changelog_entries, total_dates} ->
        entries = format_assets_changelog_entries(changelog_entries)
        total_pages = calculate_total_pages(total_dates, page_size)

        pagination = %{
          has_more: page < total_pages,
          total_dates: total_dates,
          current_page: page,
          total_pages: total_pages
        }

        result = %{
          entries: entries,
          pagination: pagination
        }

        {:ok, result}

      error ->
        {:error, "Failed to fetch assets changelog: #{inspect(error)}"}
    end
  end

  # Private helper functions

  defp format_metrics_changelog_entries(changelog_entries) do
    Enum.map(changelog_entries, fn entry ->
      %{
        date: parse_date(entry.date),
        created_metrics: format_metric_events(entry.created_metrics, :created),
        deprecated_metrics: format_metric_deprecation_events(entry.deprecated_metrics)
      }
    end)
  end

  defp format_assets_changelog_entries(changelog_entries) do
    Enum.map(changelog_entries, fn entry ->
      %{
        date: parse_date(entry.date),
        created_assets: format_asset_events(entry.created_projects, :created),
        hidden_assets: format_asset_hiding_events(entry.hidden_projects)
      }
    end)
  end

  defp format_metric_events(metric_events, _type) do
    Enum.map(metric_events, fn %{metric: metric, event: event} ->
      %{
        metric: format_metric_info(metric),
        event_timestamp: event.recorded_at
      }
    end)
  end

  defp format_metric_deprecation_events(deprecation_events) do
    Enum.map(deprecation_events, fn %{metric: metric, event: event, note: note} ->
      %{
        metric: format_metric_info(metric),
        event_timestamp: event.recorded_at,
        deprecation_note: note
      }
    end)
  end

  defp format_asset_events(asset_events, _type) do
    Enum.map(asset_events, fn %{project: project, event: event} ->
      %{
        asset: format_asset_info(project),
        event_timestamp: event.recorded_at
      }
    end)
  end

  defp format_asset_hiding_events(hiding_events) do
    Enum.map(hiding_events, fn %{project: project, event: event, reason: reason} ->
      %{
        asset: format_asset_info(project),
        event_timestamp: event.recorded_at,
        hiding_reason: reason
      }
    end)
  end

  defp format_metric_info(metric) do
    docs =
      if metric.docs && length(metric.docs) > 0 do
        Enum.map(metric.docs, fn doc -> %{link: doc.link} end)
      else
        []
      end

    %{
      human_readable_name: metric.human_readable_name,
      metric: metric.metric,
      docs: docs
    }
  end

  defp format_asset_info(project) do
    %{
      name: project.name,
      ticker: project.ticker,
      slug: project.slug,
      logo_url: project.logo_url,
      description: project.description,
      link: Project.sanbase_link(project)
    }
  end

  defp calculate_total_pages(total_count, page_size) do
    ceil(total_count / page_size)
  end

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> date_string
    end
  end

  defp parse_date(date), do: date
end
