defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Model.Project

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
           Sanbase.Clickhouse.Github.dev_activity(
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
           Sanbase.Clickhouse.Github.dev_activity(
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
        _root,
        %{
          selector: %{market_segments: market_segments},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with projects when is_list(projects) <- Project.List.by_market_segments(market_segments),
         {:ok, organizations} <- github_organizations(projects),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.dev_activity(
             organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
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
    case Sanbase.Clickhouse.Github.dev_activity(
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

  defp github_organizations(projects) when is_list(projects) do
    organizations =
      Enum.map(projects, &Project.github_organizations/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, orgs} -> orgs end)
      |> List.flatten()

    {:ok, organizations}
  end

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
           Utils.calibrate_interval(
             Sanbase.Clickhouse.Github,
             github_organizations,
             from,
             to,
             interval,
             24 * 60 * 60
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
    {:ok, Project.List.project_slugs_with_organization()}
  end
end
