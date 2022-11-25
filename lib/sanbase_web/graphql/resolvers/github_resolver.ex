defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.CalibrateInterval
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.Github
  alias Sanbase.Project

  def dev_activity(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, result} <-
           Github.dev_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, error} ->
        {:error, handle_graphql_error("dev_activity", slug, error)}
    end
  end

  def dev_activity(
        _root,
        %{
          selector: %{slug: slug},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, result} <-
           Github.dev_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, {:github_link_error, _error}} ->
        {:ok, []}

      error ->
        {:error, handle_graphql_error("dev_activity", slug, error)}
    end
  end

  def dev_activity(
        root,
        %{
          selector: %{market_segments: market_segments},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        resolution
      ) do
    args = %{
      transform: %{type: transform, moving_average_base: moving_average_interval_base},
      from: from,
      to: to,
      interval: interval,
      selector: %{}
    }

    with projects when is_list(projects) <-
           Project.List.by_market_segment_all_of(market_segments),
         slugs <- Enum.map(projects, & &1.slug),
         {:ok, result} <- get_dev_activity_many_slugs(slugs, args, root, resolution) do
      {:ok, result}
    else
      {:error, error} ->
        {:error,
         handle_graphql_error("dev_activity", market_segments, error,
           description: "market segments"
         )}
    end
  end

  def dev_activity(
        _root,
        %{
          selector: %{organizations: organizations},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    case Github.dev_activity(
           organizations,
           from,
           to,
           interval,
           transform,
           moving_average_interval_base
         ) do
      {:ok, result} ->
        {:ok, result}

      error ->
        {:error,
         handle_graphql_error("dev_activity", organizations, error, description: "organizations")}
    end
  end

  @one_day_seconds 24 * 3600
  def github_activity(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, from, to, interval} <-
           calibrate(
             Github,
             github_organizations,
             from,
             to,
             interval,
             @one_day_seconds
           ),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.github_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, error} ->
        {:error, handle_graphql_error("github_activity", slug, error)}
    end
  end

  def available_repos(_root, _args, _resolution) do
    {:ok, Project.List.slugs_with_github_organization()}
  end

  # Private functions
  defp get_dev_activity_many_slugs(slugs, args, root, resolution) do
    result =
      slugs
      |> Enum.chunk_every(500)
      |> Enum.map(fn slugs ->
        SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
          root,
          %{args | selector: %{slug: slugs}},
          Map.put(resolution, :source, %{metric: "dev_activity_1d"})
        )
      end)

    case Enum.find(result, &match?({:error, _}, &1)) do
      nil ->
        result =
          result
          |> Enum.flat_map(fn {:ok, data} -> data end)
          |> Enum.group_by(fn %{datetime: dt} -> dt end, fn %{value: value} -> value end)
          |> Enum.map(fn {datetime, values} ->
            %{datetime: datetime, activity: Enum.sum(values)}
          end)
          |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

        {:ok, result}

      error ->
        error
    end
  end
end
