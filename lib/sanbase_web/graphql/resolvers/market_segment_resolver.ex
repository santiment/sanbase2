defmodule SanbaseWeb.Graphql.Resolvers.MarketSegmentResolver do
  require Logger

  alias Sanbase.Model.{
    MarketSegment
  }

  alias Sanbase.Repo

  def all_market_segments(_parent, _args, _resolution) do
    market_segments =
      Repo.all(MarketSegment)
      |> Map.new(fn market_segment ->
        {to_snake_case(market_segment.name), market_segment.name}
      end)
      |> Map.merge(%{unknown: nil})
      |> Poison.encode!()

    {:ok, market_segments}
  end

  defp to_snake_case(string) do
    string
    |> String.downcase()
    |> String.replace(~r/'|`|"/, "")
    |> String.replace(~r/[^A-za-z0-9]/, "_")
  end
end
