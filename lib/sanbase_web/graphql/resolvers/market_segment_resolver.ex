defmodule SanbaseWeb.Graphql.Resolvers.MarketSegmentResolver do
  require Logger

  alias Sanbase.Project
  alias Sanbase.Model.MarketSegment

  alias Sanbase.Repo

  def all_market_segments(_parent, _args, _resolution) do
    filter = fn _ -> true end
    market_segments = market_segments(filter)

    {:ok, market_segments}
  end

  def erc20_market_segments(_parent, _args, _resolution) do
    filter = fn %{projects: projects} ->
      Enum.any?(projects, &Project.is_erc20?/1)
    end

    market_segments = market_segments(filter)

    {:ok, market_segments}
  end

  def currencies_market_segments(_parent, _args, _resolution) do
    filter = fn %{projects: projects} ->
      Enum.any?(projects, &Project.is_currency?/1)
    end

    market_segments = market_segments(filter)

    {:ok, market_segments}
  end

  defp market_segments(filter) do
    MarketSegment.all()
    |> Repo.preload(projects: :infrastructure)
    |> Enum.filter(filter)
    |> Enum.map(fn %{name: name, projects: projects} ->
      %{
        name: name,
        count: Enum.count(projects)
      }
    end)
  end
end
