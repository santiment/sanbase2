defmodule SanbaseWeb.Graphql.Resolvers.MarketSegmentResolver do
  require Logger

  alias Sanbase.Model.{
    MarketSegment
  }

  alias Sanbase.Repo

  def all_market_segments(_parent, _args, _resolution) do
    market_segments =
      Repo.all(MarketSegment)
      |> Repo.preload(:projects)
      |> Enum.map(fn %{name: name, projects: projects} ->
        %{
          name: name,
          count: Enum.count(projects)
        }
      end)

    {:ok, market_segments}
  end

  def erc20_market_segments(_parent, _args, _resolution) do
    market_segments =
      Repo.all(MarketSegment)
      |> Repo.preload(projects: :infrastructure)
      |> Enum.filter(fn %{projects: projects} ->
        Enum.any?(projects, fn project ->
          not is_nil(project.coinmarketcap_id) and not is_nil(project.main_contract_address) and
            not is_nil(project.infrastructure) and project.infrastructure.code === "ETH"
        end)
      end)
      |> Enum.map(fn %{name: name, projects: projects} ->
        %{
          name: name,
          count: Enum.count(projects)
        }
      end)

    {:ok, market_segments}
  end

  def currencies_market_segments(_parent, _args, _resolution) do
    market_segments =
      Repo.all(MarketSegment)
      |> Repo.preload(projects: :infrastructure)
      |> Enum.filter(fn %{projects: projects} ->
        Enum.any?(projects, fn project ->
          not is_nil(project.coinmarketcap_id) and
            (is_nil(project.main_contract_address) or
               (not is_nil(project.infrastructure) and project.infrastructure.code !== "ETH"))
        end)
      end)
      |> Enum.map(fn %{name: name, projects: projects} ->
        %{
          name: name,
          count: Enum.count(projects)
        }
      end)

    {:ok, market_segments}
  end
end
