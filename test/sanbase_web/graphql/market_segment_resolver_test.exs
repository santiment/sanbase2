defmodule SanbaseWeb.Graphql.MarketSegmentResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    ms1 = insert(:market_segment, %{name: "Foo"})
    ms2 = insert(:market_segment, %{name: "Bar"})
    ms3 = insert(:market_segment, %{name: "Qux"})

    insert(:market_segment, %{name: "Baz"})

    insert(:random_erc20_project, %{market_segments: [ms1]})
    insert(:random_project, %{market_segments: [ms2]})
    insert(:random_project, %{market_segments: [ms3]})

    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  test "all_market_segments/3", %{conn: conn} do
    market_segments =
      conn
      |> market_segments_query("allMarketSegments")
      |> json_response(200)
      |> extract_all_market_segments()

    market_segments = Enum.sort_by(market_segments, & &1["name"])

    expected_market_segments =
      Enum.sort_by(
        [
          %{"count" => 1, "name" => "Foo"},
          %{"count" => 1, "name" => "Bar"},
          %{"count" => 0, "name" => "Baz"},
          %{"count" => 1, "name" => "Qux"}
        ],
        & &1["name"]
      )

    assert Enum.count(market_segments) === 4

    assert market_segments == expected_market_segments
  end

  test "erc20_market_segments/3", %{conn: conn} do
    market_segments =
      conn
      |> market_segments_query("erc20MarketSegments")
      |> json_response(200)
      |> extract_erc20_market_segments()

    assert Enum.count(market_segments) === 1

    assert market_segments === [
             %{"count" => 1, "name" => "Foo"}
           ]
  end

  test "currencies_market_segments/3", %{conn: conn} do
    market_segments =
      conn
      |> market_segments_query("currenciesMarketSegments")
      |> json_response(200)
      |> extract_currencies_market_segments()

    assert Enum.count(market_segments) === 2

    assert market_segments === [
             %{"count" => 1, "name" => "Bar"},
             %{"count" => 1, "name" => "Qux"}
           ]
  end

  defp market_segments_query(conn, query_name) do
    query = """
    {
      #{query_name} {
        name
        count
      }
    }
    """

    post(conn, "/graphql", query_skeleton(query, query_name))
  end

  defp extract_all_market_segments(%{"data" => %{"allMarketSegments" => all_market_segments}}) do
    all_market_segments
  end

  defp extract_erc20_market_segments(%{"data" => %{"erc20MarketSegments" => erc20_market_segments}}) do
    erc20_market_segments
  end

  defp extract_currencies_market_segments(%{"data" => %{"currenciesMarketSegments" => currencies_market_segments}}) do
    currencies_market_segments
  end
end
