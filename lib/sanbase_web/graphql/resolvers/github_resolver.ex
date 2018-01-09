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
        %{ticker: ticker, from: from, to: to, interval: interval, transform: "movingAverage"},
        _resolution
      ) do
    result =
    Store.fetch_moving_average_for_hours!(ticker, from, to, interval)
    |> Enum.map(fn {datetime, activity} -> %{datetime: datetime, activity: activity} end)

    {:ok, result}
  end

  def available_repos(_root, _args, _resolution) do
    Store.list_measurements() # returns {:ok, result} | {:error, error}
  end
end