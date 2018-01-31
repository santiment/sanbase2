defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  alias Sanbase.Github.Store

  def activity(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval, transform: "None"},
        _resolution
      ) do
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
          moving_average_interval: ma_interval
        },
        _resolution
      ) do
    result =
      Store.fetch_moving_average_for_hours!(ticker, from, to, interval, ma_interval)
      |> Enum.map(fn {datetime, activity} -> %{datetime: datetime, activity: activity} end)

    {:ok, result}
  end

  def available_repos(_root, _args, _resolution) do
    # returns {:ok, result} | {:error, error}
    Store.list_measurements()
  end
end
