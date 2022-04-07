defmodule SanbaseWeb.Graphql.GetMostRecentApitest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  defp seconds_ago(seconds) do
    Timex.shift(DateTime.utc_now(), seconds: -seconds)
  end

  test "get most recent insights", %{conn: conn} do
    insight1 = insert(:published_post, inserted_at: seconds_ago(30))
    _unpublished = insert(:post, inserted_at: seconds_ago(25))
    insight2 = insert(:published_post, inserted_at: seconds_ago(20))
    _unpublished = insert(:post, inserted_at: seconds_ago(15))
    insight3 = insert(:published_post, inserted_at: seconds_ago(10))
    insight4 = insert(:published_post, inserted_at: seconds_ago(5))

    result = get_most_recent(conn, :insight)
    assert length(result) == 4
    assert Enum.at(result, 0)["insight"]["id"] == insight4.id
    assert Enum.at(result, 1)["insight"]["id"] == insight3.id
    assert Enum.at(result, 2)["insight"]["id"] == insight2.id
    assert Enum.at(result, 3)["insight"]["id"] == insight1.id
  end

  test "get most recent screener", %{conn: conn} do
    # The non-screener should not be in the result
    _not_screener = insert(:watchlist, is_public: true, inserted_at: seconds_ago(50))
    screener1 = insert(:screener, is_public: true, inserted_at: seconds_ago(45))
    screener2 = insert(:screener, is_public: true, inserted_at: seconds_ago(40))
    screener3 = insert(:screener, is_public: true, inserted_at: seconds_ago(35))
    _private = insert(:screener, is_public: false, inserted_at: seconds_ago(30))
    _private = insert(:screener, is_public: false, inserted_at: seconds_ago(25))
    screener4 = insert(:screener, is_public: true, inserted_at: seconds_ago(20))

    result = get_most_recent(conn, :screener)
    assert length(result) == 4
    assert Enum.at(result, 0)["screener"]["id"] |> String.to_integer() == screener4.id
    assert Enum.at(result, 1)["screener"]["id"] |> String.to_integer() == screener3.id
    assert Enum.at(result, 2)["screener"]["id"] |> String.to_integer() == screener2.id
    assert Enum.at(result, 3)["screener"]["id"] |> String.to_integer() == screener1.id
  end

  test "get most recent watchlist", %{conn: conn} do
    # The screener should not be in the result
    watchlist1 = insert(:watchlist, is_public: true, inserted_at: seconds_ago(30))
    _private = insert(:watchlist, is_public: false, inserted_at: seconds_ago(25))
    _private = insert(:watchlist, is_public: false, inserted_at: seconds_ago(20))
    watchlist2 = insert(:watchlist, is_public: true, inserted_at: seconds_ago(15))
    watchlist3 = insert(:watchlist, is_public: true, inserted_at: seconds_ago(10))
    _screener = insert(:screener, is_public: true, inserted_at: seconds_ago(5))
    watchlist4 = insert(:watchlist, is_public: true, inserted_at: seconds_ago(0))

    result = get_most_recent(conn, :watchlist)
    assert length(result) == 4
    assert Enum.at(result, 0)["watchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(result, 1)["watchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(result, 2)["watchlist"]["id"] |> String.to_integer() == watchlist2.id
    assert Enum.at(result, 3)["watchlist"]["id"] |> String.to_integer() == watchlist1.id
  end

  test "get most recent chart configuration", %{conn: conn} do
    chart_configuration1 = insert(:chart_configuration, is_public: true)
    chart_configuration2 = insert(:chart_configuration, is_public: true)
    _private = insert(:chart_configuration, is_public: false)
    _private = insert(:chart_configuration, is_public: false)
    chart_configuration3 = insert(:chart_configuration, is_public: true)
    chart_configuration4 = insert(:chart_configuration, is_public: true)

    result = get_most_recent(conn, :chart_configuration)
    assert length(result) == 4

    assert Enum.at(result, 0)["chartConfiguration"]["id"] == chart_configuration4.id
    assert Enum.at(result, 1)["chartConfiguration"]["id"] == chart_configuration3.id
    assert Enum.at(result, 2)["chartConfiguration"]["id"] == chart_configuration2.id
    assert Enum.at(result, 3)["chartConfiguration"]["id"] == chart_configuration1.id
  end

  defp get_most_recent(conn, entity) do
    query = """
    {
      getMostRecent(
        type: #{entity |> Atom.to_string() |> String.upcase()}
        page: 1
        pageSize: 10
      ){
          insight{ id }
          watchlist{ id }
          screener{ id }
          chartConfiguration{ id }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostRecent"])
  end
end
