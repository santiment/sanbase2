defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  alias Sanbase.Github.Store

  def activity(
        _root,
        %{repository: repository, from: from, to: to, interval: interval},
        _resolution
      ) do
    result =
    Store.fetch_activity_with_resolution!(repository, from, to, interval)
    |> Enum.map(fn {datetime, activity} -> %{datetime: datetime, activity: activity} end)

    {:ok, result}
  end

  def available_repos(_root, _args, _resolution) do
    Store.list_measurements() # returns {:ok, result} | {:error, error}
  end
end