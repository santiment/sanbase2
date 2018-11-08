defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Model.Project
  alias Sanbase.Github.Store

  def dev_activity(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    github_organization = Project.github_organization(slug)

    with {:ok, result} <-
           Sanbase.Clickhouse.Github.activity(github_organization, from, to, interval) do
      {:ok, result}
    else
      error ->
        Logger.error("Cannot fetch github activity for #{slug}. Reason: #{inspect(error)}")
        {:error, "Cannot fetch github activity for #{slug}"}
    end
  end

  def activity(root, %{slug: slug} = args, resolution) do
    # Temporary solution while all frontend queries migrate to using slug. After that
    # only the slug query will remain
    if ticker = Project.ticker_by_slug(slug) do
      args = args |> Map.delete(:slug) |> Map.put(:ticker, ticker)
      activity(root, args, resolution)
    else
      {:ok, []}
    end
  end

  def activity(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval, transform: "None"},
        _resolution
      ) do
    ticker = correct_ticker(ticker)

    {:ok, from, to, interval} =
      Utils.calibrate_interval(Store, ticker, from, to, interval, 24 * 60 * 60)

    result =
      Store.fetch_activity_with_resolution!(ticker, from, to, interval)
      |> Enum.map(fn {datetime, activity} -> %{datetime: datetime, activity: activity} end)

    {:ok, result}
  end

  def activity(
        _root,
        %{
          ticker: ticker,
          from: from,
          to: to,
          interval: interval,
          transform: "movingAverage",
          moving_average_interval_base: ma_base
        },
        _resolution
      ) do
    ticker = correct_ticker(ticker)

    {:ok, from, to, interval, ma_interval} =
      Utils.calibrate_interval_with_ma_interval(
        Store,
        ticker,
        from,
        to,
        interval,
        24 * 60 * 60,
        ma_base,
        300
      )

    result =
      Store.fetch_moving_average_for_hours!(ticker, from, to, interval, ma_interval)
      |> Enum.map(fn {datetime, activity} -> %{datetime: datetime, activity: activity} end)

    {:ok, result}
  end

  def available_repos(_root, _args, _resolution) do
    # returns {:ok, result} | {:error, error}
    Store.list_measurements()
  end

  defp correct_ticker("MKR"), do: "DAI"
  defp correct_ticker("DGX"), do: "DGD"
  defp correct_ticker(ticker), do: ticker
end
