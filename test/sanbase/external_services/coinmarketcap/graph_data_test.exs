defmodule Sanbase.ExternalServices.Coinmarketmap.GraphDataTest do
  use ExUnit.Case, async: true

  alias Sanbase.ExternalServices.Coinmarketmap.GraphData

  test "parsing the coinbase json graph data" do
    points = File.read!(Path.join(__DIR__, "btc_graph_data.json"))
    |> GraphData.parse_json
    |> Enum.to_list

    assert length(points) > 0
    assert hd(points).datetime == DateTime.from_unix!(1507991665000, :millisecond)
  end
end
