defmodule SanbaseWeb.Graphql.MostVotedApitest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Timeline.TimelineEvent

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "get most voted insight", %{conn: conn} do
    insight1 = insert(:published_post)
    insight2 = insert(:published_post)
    insight_without_votes1 = insert(:published_post)
    insight_without_votes2 = insert(:published_post)

    for _ <- 1..10, do: vote(conn, "insightId", insight1.id)
    for _ <- 1..5, do: vote(conn, "insightId", insight2.id)

    result = get_most_voted(conn, :insight)
    assert length(result) == 4
    assert Enum.at(result, 0)["insight"]["id"] == insight1.id
    assert Enum.at(result, 1)["insight"]["id"] == insight2.id
    assert Enum.at(result, 2)["insight"]["id"] == insight_without_votes2.id
    assert Enum.at(result, 3)["insight"]["id"] == insight_without_votes1.id
  end

  test "get most voted screener", %{conn: conn} do
    # The non-screener should not be in the result
    watchlist0 = insert(:watchlist, is_public: true, is_screener: false)
    watchlist1 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist2 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist_without_votes1 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist_without_votes2 = insert(:watchlist, is_public: true, is_screener: true)

    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :screener)
    assert length(result) == 4
    assert Enum.at(result, 0)["screener"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(result, 1)["screener"]["id"] |> String.to_integer() == watchlist2.id

    # The entities without votes are ordered from newest to oldest
    assert Enum.at(result, 2)["screener"]["id"] |> String.to_integer() ==
             watchlist_without_votes2.id

    assert Enum.at(result, 3)["screener"]["id"] |> String.to_integer() ==
             watchlist_without_votes1.id
  end

  test "get most voted watchlist", %{conn: conn} do
    # The screener should not be in the result
    watchlist0 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist1 = insert(:watchlist, is_public: true, is_screener: false)
    watchlist2 = insert(:watchlist, is_public: true, is_screener: false)
    watchlist_without_votes1 = insert(:watchlist, is_public: true, is_screener: false)
    watchlist_without_votes2 = insert(:watchlist, is_public: true, is_screener: false)

    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :watchlist)
    assert length(result) == 4
    assert Enum.at(result, 0)["watchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(result, 1)["watchlist"]["id"] |> String.to_integer() == watchlist2.id

    # The entities without votes are ordered from newest to oldest
    assert Enum.at(result, 2)["watchlist"]["id"] |> String.to_integer() ==
             watchlist_without_votes2.id

    assert Enum.at(result, 3)["watchlist"]["id"] |> String.to_integer() ==
             watchlist_without_votes1.id
  end

  test "get most voted timeline event", %{conn: conn, user: user} do
    te_opts = [
      user_list: insert(:watchlist, is_public: true),
      user: user,
      event_type: TimelineEvent.update_watchlist_type()
    ]

    timeline_event1 = insert(:timeline_event, te_opts)
    timeline_event2 = insert(:timeline_event, te_opts)
    timeline_event_without_votes1 = insert(:timeline_event, te_opts)
    timeline_event_without_votes2 = insert(:timeline_event, te_opts)

    for _ <- 1..10, do: vote(conn, "timelineEventId", timeline_event1.id)
    for _ <- 1..5, do: vote(conn, "timelineEventId", timeline_event2.id)

    result = get_most_voted(conn, :timeline_event)
    assert length(result) == 4
    assert Enum.at(result, 0)["timelineEvent"]["id"] == timeline_event1.id
    assert Enum.at(result, 1)["timelineEvent"]["id"] == timeline_event2.id
    # The entities without votes are ordered from newest to oldest
    assert Enum.at(result, 2)["timelineEvent"]["id"] == timeline_event_without_votes2.id
    assert Enum.at(result, 3)["timelineEvent"]["id"] == timeline_event_without_votes1.id
  end

  test "get most voted chart configuration", %{conn: conn} do
    chart_configuration1 = insert(:chart_configuration, is_public: true)
    chart_configuration2 = insert(:chart_configuration, is_public: true)
    chart_configuration_without_votes1 = insert(:chart_configuration, is_public: true)
    chart_configuration_without_votes2 = insert(:chart_configuration, is_public: true)

    for _ <- 1..10, do: vote(conn, "chartConfigurationId", chart_configuration1.id)
    for _ <- 1..5, do: vote(conn, "chartConfigurationId", chart_configuration2.id)

    result = get_most_voted(conn, :chart_configuration)
    assert length(result) == 4

    assert Enum.at(result, 0)["chartConfiguration"]["id"] ==
             chart_configuration1.id

    assert Enum.at(result, 1)["chartConfiguration"]["id"] ==
             chart_configuration2.id

    # The entities without votes are ordered from newest to oldest
    assert Enum.at(result, 2)["chartConfiguration"]["id"] ==
             chart_configuration_without_votes2.id

    assert Enum.at(result, 3)["chartConfiguration"]["id"] ==
             chart_configuration_without_votes1.id
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

  defp get_most_voted(conn, entity) do
    query = """
    {
    getMostVoted(
    type: #{entity |> Atom.to_string() |> String.upcase()}
    page: 1
    pageSize: 10){
      insight{ id }
      watchlist{ id }
      screener{ id }
      timelineEvent{ id }
      chartConfiguration{ id }
    }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostVoted"])
  end
end
