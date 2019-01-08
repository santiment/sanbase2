defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

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
    with {:ok, github_organization} <- Project.github_organization(slug),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.dev_activity(
             github_organization,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, {:github_link_error, error}} ->
        {:ok, []}

      error ->
        Logger.error("Cannot fetch github activity for #{slug}. Reason: #{inspect(error)}")
        {:error, "Cannot fetch github activity for #{slug}"}
    end
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
    with {:ok, github_organization} <- Project.github_organization(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Sanbase.Clickhouse.Github,
             github_organization,
             from,
             to,
             interval,
             24 * 60 * 60
           ),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.github_activity(
             github_organization,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, {:github_link_error, error}} ->
        {:ok, []}

      error ->
        Logger.error("Cannot fetch github activity for #{slug}. Reason: #{inspect(error)}")
        {:error, "Cannot fetch github activity for #{slug}"}
    end
  end

  def available_repos(_root, _args, _resolution) do
    # TODO
    {:ok, []}
  end

  defp correct_ticker("MKR"), do: "DAI"
  defp correct_ticker("DGX"), do: "DGD"
  defp correct_ticker(ticker), do: ticker
end
