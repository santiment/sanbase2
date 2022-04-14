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
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["insight"]["id"] == insight1.id
    assert Enum.at(data, 1)["insight"]["id"] == insight2.id
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
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most voted project watchlist", %{conn: conn} do
    # The screener should not be in the result
    screener0 = insert(:screener, type: :project, is_public: true)

    watchlist0 =
      insert(:watchlist,
        type: :project,
        is_public: true,
        inserted_at: days_ago()
      )

    watchlist1 = insert(:watchlist, type: :project, is_public: true)
    watchlist2 = insert(:watchlist, type: :project, is_public: true)

    _watchlsit_without_votes = insert(:watchlist, type: :project, is_public: true)

    for _ <- 1..20, do: vote(conn, "watchlistId", screener0.id)
    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :project_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most voted address watchlist", %{conn: conn} do
    # The screener should not be in the result
    screener0 = insert(:screener, type: :blockchain_address, is_public: true)

    watchlist0 =
      insert(:watchlist,
        type: :blockchain_address,
        is_public: true,
        inserted_at: days_ago()
      )

    watchlist1 = insert(:watchlist, type: :blockchain_address, is_public: true)
    watchlist2 = insert(:watchlist, type: :blockchain_address, is_public: true)

    _watchlsit_without_votes = insert(:watchlist, type: :blockchain_address, is_public: true)

    for _ <- 1..20, do: vote(conn, "watchlistId", screener0.id)
    for _ <- 1..20, do: vote(conn, "watchlistId", watchlist0.id)
    for _ <- 1..10, do: vote(conn, "watchlistId", watchlist1.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", watchlist2.id)

    result = get_most_voted(conn, :address_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(data, 1)["addressWatchlist"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most voted chart configuration", %{conn: conn} do
    chart_configuration0 = insert(:chart_configuration, is_public: true, inserted_at: days_ago())

    chart_configuration1 = insert(:chart_configuration, is_public: true)
    chart_configuration2 = insert(:chart_configuration, is_public: true)

    _chart_configuration_without_vote = insert(:chart_configuration, is_public: true)

    for _ <- 1..10,
        do: vote(conn, "chartConfigurationId", chart_configuration0.id)

    for _ <- 1..10,
        do: vote(conn, "chartConfigurationId", chart_configuration1.id)

    for _ <- 1..5,
        do: vote(conn, "chartConfigurationId", chart_configuration2.id)

    result = get_most_voted(conn, :chart_configuration)
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["chartConfiguration"]["id"] == chart_configuration1.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == chart_configuration2.id
  end

  test "get most voted user trigger", %{conn: conn} do
    trigger0 = insert(:user_trigger, is_public: true, inserted_at: days_ago())
    trigger1 = insert(:user_trigger, is_public: true)
    trigger2 = insert(:user_trigger, is_public: true)
    _trigger_without_vote = insert(:user_trigger, is_public: true)

    for _ <- 1..10, do: vote(conn, "userTriggerId", trigger0.id)
    for _ <- 1..10, do: vote(conn, "userTriggerId", trigger1.id)
    for _ <- 1..5, do: vote(conn, "userTriggerId", trigger2.id)

    result = get_most_voted(conn, :user_trigger)
    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 2, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 2
    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == trigger1.id
    assert Enum.at(data, 1)["userTrigger"]["trigger"]["id"] == trigger2.id
  end

  test "get most voted combined", %{conn: conn} do
    insight1 = insert(:published_post)
    insight2 = insert(:published_post)
    conf1 = insert(:chart_configuration, is_public: true)
    conf2 = insert(:chart_configuration, is_public: true)
    screener = insert(:screener, is_public: true)
    project_watchlist = insert(:watchlist, type: :project, is_public: true)

    address_watchlist = insert(:watchlist, type: :blockchain_address, is_public: true)

    user_trigger = insert(:user_trigger, is_public: true)

    for _ <- 1..10, do: vote(conn, "insightId", insight1.id)
    for _ <- 1..9, do: vote(conn, "insightId", insight2.id)
    for _ <- 1..8, do: vote(conn, "chartConfigurationId", conf2.id)
    for _ <- 1..7, do: vote(conn, "chartConfigurationId", conf1.id)
    for _ <- 1..6, do: vote(conn, "watchlistId", project_watchlist.id)
    for _ <- 1..5, do: vote(conn, "watchlistId", screener.id)
    for _ <- 1..4, do: vote(conn, "watchlistId", address_watchlist.id)
    for _ <- 1..3, do: vote(conn, "userTriggerId", user_trigger.id)

    # Get with default page = 1 and pageSize = 10, all entities are returned
    result =
      get_most_voted(conn, [
        :insight,
        :project_watchlist,
        :address_watchlist,
        :screener,
        :chart_configuration,
        :user_trigger
      ])

    data = result["data"]
    stats = result["stats"]

    assert %{"totalEntitiesCount" => 8, "currentPage" => 1, "currentPageSize" => 10} = stats

    assert length(data) == 8
    assert Enum.at(data, 0)["insight"]["id"] == insight1.id
    assert Enum.at(data, 1)["insight"]["id"] == insight2.id
    assert Enum.at(data, 2)["chartConfiguration"]["id"] == conf2.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == conf1.id

    assert Enum.at(data, 4)["projectWatchlist"]["id"] |> String.to_integer() ==
             project_watchlist.id

    assert Enum.at(data, 5)["screener"]["id"] |> String.to_integer() ==
             screener.id

    assert Enum.at(data, 6)["addressWatchlist"]["id"] |> String.to_integer() ==
             address_watchlist.id

    assert Enum.at(data, 7)["userTrigger"]["trigger"]["id"] == user_trigger.id

    # Get with page: 3, page_size: 2
    result =
      get_most_voted(
        conn,
        [
          :insight,
          :project_watchlist,
          :address_watchlist,
          :screener,
          :chart_configuration,
          :user_trigger
        ],
        page: 3,
        page_size: 2
      )

    data = result["data"]
    stats = result["stats"]
    assert %{"totalEntitiesCount" => 8, "currentPage" => 3, "currentPageSize" => 2} = stats

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() ==
             project_watchlist.id

    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() ==
             screener.id
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

  defp get_most_voted(conn, entity_or_entities, opts \\ [])

  defp get_most_voted(conn, entities, opts) when is_list(entities) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)

    types =
      Enum.map(entities, &(&1 |> Atom.to_string() |> String.upcase()))
      |> Enum.join(", ")

    query = """
    {
      getMostVoted(
        types: [#{types}]
        page: #{page}
        pageSize: #{page_size}
        cursor: { type: AFTER, datetime: "utc_now-7d" }
      ){
        stats { currentPage currentPageSize totalEntitiesCount }
        data {
          insight{ id }
          projectWatchlist{ id }
          addressWatchlist{ id }
          screener{ id }
          chartConfiguration{ id }
          userTrigger{ trigger{ id } }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostVoted"])
  end

  defp get_most_voted(conn, entity, opts) when is_atom(entity) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)

    query = """
    {
      getMostVoted(
        type: #{entity |> Atom.to_string() |> String.upcase()}
        page: #{page}
        pageSize: #{page_size}
        cursor: { type: AFTER, datetime: "utc_now-7d" }
      ){
        stats { currentPage currentPageSize totalEntitiesCount }
        data {
          insight{ id }
          projectWatchlist{ id }
          addressWatchlist{ id }
          screener{ id }
          chartConfiguration{ id }
          userTrigger{ trigger{ id } }
        }
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
