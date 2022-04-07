defmodule SanbaseWeb.Graphql.GetMostVotedApitest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "get most voted insight", %{conn: conn} do
    _ = insert(:published_post, published_at: days_ago())
    insight1 = insert(:published_post)
    insight2 = insert(:published_post)
    _insight_without_votes = insert(:published_post)

    for _ <- 1..10, do: vote(conn, "insightId", insight1.id)
    for _ <- 1..5, do: vote(conn, "insightId", insight2.id)

    result = get_most_voted(conn, :insight)
    assert length(result) == 2
    assert Enum.at(result, 0)["insight"]["id"] == insight1.id
    assert Enum.at(result, 1)["insight"]["id"] == insight2.id
  end

  test "get most voted screener", %{conn: conn} do
    # The non-screener should not be in the result
    watchlist0 = insert(:watchlist, is_public: true)
    screener0 = insert(:screener, is_public: true, inserted_at: days_ago())

    watchlist1 = insert(:screener, is_public: true)
    watchlist2 = insert(:screener, is_public: true)
    _watchlist_without_votes = insert(:screener, is_public: true)

    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..20, do: vote(conn, "watchlistId", screener0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :screener)
    assert length(result) == 2
    assert Enum.at(result, 0)["screener"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(result, 1)["screener"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most voted watchlist", %{conn: conn} do
    # The screener should not be in the result
    screener0 = insert(:screener, is_public: true)
    watchlist0 = insert(:watchlist, is_public: true, inserted_at: days_ago())

    watchlist1 = insert(:watchlist, is_public: true)
    watchlist2 = insert(:watchlist, is_public: true)
    _watchlsit_without_votes = insert(:watchlist, is_public: true)

    for _ <- 1..20, do: vote(conn, "watchlistId", screener0.id)
    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :watchlist)
    assert length(result) == 2
    assert Enum.at(result, 0)["watchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(result, 1)["watchlist"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most voted chart configuration", %{conn: conn} do
    chart_configuration0 = insert(:chart_configuration, is_public: true, inserted_at: days_ago())

    chart_configuration1 = insert(:chart_configuration, is_public: true)

    chart_configuration2 = insert(:chart_configuration, is_public: true)

    _chart_configuration_without_vote = insert(:chart_configuration, is_public: true)

    for _ <- 1..10, do: vote(conn, "chartConfigurationId", chart_configuration0.id)
    for _ <- 1..10, do: vote(conn, "chartConfigurationId", chart_configuration1.id)
    for _ <- 1..5, do: vote(conn, "chartConfigurationId", chart_configuration2.id)

    result = get_most_voted(conn, :chart_configuration)
    assert length(result) == 2

    assert Enum.at(result, 0)["chartConfiguration"]["id"] ==
             chart_configuration1.id

    assert Enum.at(result, 1)["chartConfiguration"]["id"] ==
             chart_configuration2.id
  end

  test "get most voted combined", %{conn: conn} do
    insight1 = insert(:published_post)
    insight2 = insert(:published_post)
    conf1 = insert(:chart_configuration, is_public: true)
    conf2 = insert(:chart_configuration, is_public: true)
    screener1 = insert(:screener, is_public: true)
    watchlist1 = insert(:watchlist, is_public: true)

    for _ <- 1..10, do: vote(conn, "insightId", insight1.id)
    for _ <- 1..9, do: vote(conn, "insightId", insight2.id)
    for _ <- 1..8, do: vote(conn, "chartConfigurationId", conf2.id)
    for _ <- 1..7, do: vote(conn, "chartConfigurationId", conf1.id)
    for _ <- 1..6, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", screener1.id)

    result = get_most_voted(conn, [:insight, :watchlist, :screener, :chart_configuration])

    assert length(result) == 6
    assert Enum.at(result, 0)["insight"]["id"] == insight1.id
    assert Enum.at(result, 1)["insight"]["id"] == insight2.id
    assert Enum.at(result, 2)["chartConfiguration"]["id"] == conf2.id
    assert Enum.at(result, 3)["chartConfiguration"]["id"] == conf1.id
    assert Enum.at(result, 4)["watchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(result, 5)["screener"]["id"] |> String.to_integer() == screener1.id
  end

  defp vote(conn, entity_key, entity_id) do
    mutation = """
    mutation {
      vote(#{entity_key}: #{entity_id}) {
        votes{
          totalVotes totalVoters currentUserVotes
        }
      }
    }
    """

    %{} =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
      |> get_in(["data", "vote"])
  end

  defp get_most_voted(conn, entities) when is_list(entities) do
    types = Enum.map(entities, &(&1 |> Atom.to_string() |> String.upcase())) |> Enum.join(", ")

    query = """
    {
      getMostVoted(
        types: [#{types}]
        page: 1
        pageSize: 10
        cursor: { type: AFTER, datetime: "utc_now-7d" }
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
    |> get_in(["data", "getMostVoted"])
  end

  defp get_most_voted(conn, entity) do
    query = """
    {
      getMostVoted(
        type: #{entity |> Atom.to_string() |> String.upcase()}
        page: 1
        pageSize: 10
        cursor: { type: AFTER, datetime: "utc_now-7d" }
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
    |> get_in(["data", "getMostVoted"])
  end

  defp days_ago() do
    Timex.shift(Timex.now(), days: -10)
  end
end
