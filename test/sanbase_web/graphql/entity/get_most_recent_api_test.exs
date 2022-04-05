defmodule SanbaseWeb.Graphql.GetMostRecentApitest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Timeline.TimelineEvent

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "get most recent insights", %{conn: conn} do
    insight1 = insert(:published_post)
    _unpublished = insert(:post)
    insight2 = insert(:published_post)
    _unpublished = insert(:post)
    insight3 = insert(:published_post)
    insight4 = insert(:published_post)

    result = get_most_recent(conn, :insight)
    assert length(result) == 4
    assert Enum.at(result, 0)["insight"]["id"] == insight4.id
    assert Enum.at(result, 1)["insight"]["id"] == insight3.id
    assert Enum.at(result, 2)["insight"]["id"] == insight2.id
    assert Enum.at(result, 3)["insight"]["id"] == insight1.id
  end

  test "get most voted screener", %{conn: conn} do
    # The non-screener should not be in the result
    _not_screener = insert(:watchlist, is_public: true, is_screener: false)
    watchlist1 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist2 = insert(:watchlist, is_public: true, is_screener: true)
    watchlist3 = insert(:watchlist, is_public: true, is_screener: true)
    _private = insert(:watchlist, is_public: false, is_screener: true)
    _private = insert(:watchlist, is_public: false, is_screener: true)
    watchlist4 = insert(:watchlist, is_public: true, is_screener: true)

    result = get_most_recent(conn, :screener)
    assert length(result) == 4
    assert Enum.at(result, 0)["screener"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(result, 1)["screener"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(result, 2)["screener"]["id"] |> String.to_integer() == watchlist2.id
    assert Enum.at(result, 3)["screener"]["id"] |> String.to_integer() == watchlist1.id
  end

  test "get most voted watchlist", %{conn: conn} do
    # The screener should not be in the result
    watchlist1 = insert(:watchlist, is_public: true, is_screener: false)
    _private = insert(:watchlist, is_public: false, is_screener: false)
    _private = insert(:watchlist, is_public: false, is_screener: false)
    watchlist2 = insert(:watchlist, is_public: true, is_screener: false)
    watchlist3 = insert(:watchlist, is_public: true, is_screener: false)
    _screener = insert(:watchlist, is_public: true, is_screener: true)
    watchlist4 = insert(:watchlist, is_public: true, is_screener: false)

    result = get_most_recent(conn, :watchlist)
    assert length(result) == 4
    assert Enum.at(result, 0)["watchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(result, 1)["watchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(result, 2)["watchlist"]["id"] |> String.to_integer() == watchlist2.id
    assert Enum.at(result, 3)["watchlist"]["id"] |> String.to_integer() == watchlist1.id
  end

  test "get most voted timeline event", %{conn: conn, user: user} do
    te_opts = [
      user_list: insert(:watchlist, is_public: true),
      user: user,
      event_type: TimelineEvent.update_watchlist_type()
    ]

    private_watchlist = insert(:watchlist, is_public: false)

    timeline_event1 = insert(:timeline_event, te_opts)
    timeline_event2 = insert(:timeline_event, te_opts)
    _not_public_entity = insert(:timeline_event, user_list: private_watchlist)
    timeline_event3 = insert(:timeline_event, te_opts)
    timeline_event4 = insert(:timeline_event, te_opts)
    _not_public_entity = insert(:timeline_event, user_list: private_watchlist)

    result = get_most_recent(conn, :timeline_event)
    assert length(result) == 4
    assert Enum.at(result, 0)["timelineEvent"]["id"] == timeline_event4.id
    assert Enum.at(result, 1)["timelineEvent"]["id"] == timeline_event3.id
    assert Enum.at(result, 2)["timelineEvent"]["id"] == timeline_event2.id
    assert Enum.at(result, 3)["timelineEvent"]["id"] == timeline_event1.id
  end

  test "get most voted chart configuration", %{conn: conn} do
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
          timelineEvent{ id }
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
