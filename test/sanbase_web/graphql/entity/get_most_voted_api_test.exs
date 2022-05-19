defmodule SanbaseWeb.Graphql.GetMostVotedApitest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    _role = insert(:role_san_family)
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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

    assert length(data) == 2

    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() ==
             watchlist1.id

    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() ==
             watchlist2.id
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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

    assert length(data) == 2

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() ==
             watchlist1.id

    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() ==
             watchlist2.id
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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

    assert length(data) == 2

    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() ==
             watchlist1.id

    assert Enum.at(data, 1)["addressWatchlist"]["id"] |> String.to_integer() ==
             watchlist2.id
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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

    assert length(data) == 2

    assert Enum.at(data, 0)["chartConfiguration"]["id"] ==
             chart_configuration1.id

    assert Enum.at(data, 1)["chartConfiguration"]["id"] ==
             chart_configuration2.id
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

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

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

    assert %{
             "totalEntitiesCount" => 8,
             "currentPage" => 1,
             "currentPageSize" => 10,
             "totalPagesCount" => 1
           } = stats

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

    assert %{
             "totalEntitiesCount" => 8,
             "currentPage" => 3,
             "currentPageSize" => 2,
             "totalPagesCount" => 4
           } = stats

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() ==
             project_watchlist.id

    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() ==
             screener.id
  end

  test "get most voted with projects' slugs filter", context do
    %{conn: conn} = context
    to_ids = fn projects -> Enum.map(projects, &%{project_id: &1.id}) end
    # projects
    pl = [p1, p2, p3, p4] = for slug <- ["p1", "p2", "p3", "p4"], do: insert(:project, slug: slug)

    [w1, w2, w3, _w4] =
      for p_list <- [[p1, p2, p3], [p2, p3], [p3, p4], [p4]] do
        w = insert(:watchlist, type: :project, is_public: true)

        {:ok, w} =
          Sanbase.UserList.update_user_list(context.user, %{id: w.id, list_items: to_ids.(p_list)})

        w
      end

    [_i1, i2, i3, _i4] = for p <- pl, do: insert(:published_post, price_chart_project: p)

    [_c1, c2, c3, _c4] =
      for p <- pl, do: insert(:chart_configuration, is_public: true, project: p)

    [_a1, a2, a3, _a4] = for p <- pl, do: create_alert(context.user, p)

    for _ <- 1..10, do: vote(conn, "watchlistId", w1.id)
    for _ <- 1..9, do: vote(conn, "insightId", i2.id)
    for _ <- 1..8, do: vote(conn, "insightId", i3.id)
    for _ <- 1..7, do: vote(conn, "watchlistId", w3.id)
    for _ <- 1..6, do: vote(conn, "watchlistId", w2.id)
    for _ <- 1..5, do: vote(conn, "userTriggerId", a3.id)
    for _ <- 1..4, do: vote(conn, "chartConfigurationId", c2.id)
    for _ <- 1..3, do: vote(conn, "chartConfigurationId", c3.id)
    for _ <- 1..2, do: vote(conn, "userTriggerId", a2.id)

    result =
      get_most_voted(
        conn,
        [:project_watchlist, :insight, :chart_configuration, :user_trigger],
        filter: %{slugs: [p2.slug, p3.slug]}
      )

    data = result["data"]
    stats = result["stats"]

    # Expect: w1, i1, c1, a1
    assert %{
             "totalEntitiesCount" => 9,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == w1.id
    assert Enum.at(data, 1)["insight"]["id"] == i2.id
    assert Enum.at(data, 2)["insight"]["id"] == i3.id
    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() == w3.id
    assert Enum.at(data, 4)["projectWatchlist"]["id"] |> String.to_integer() == w2.id
    assert Enum.at(data, 5)["userTrigger"]["trigger"]["id"] == a3.id
    assert Enum.at(data, 6)["chartConfiguration"]["id"] == c2.id
    assert Enum.at(data, 7)["chartConfiguration"]["id"] == c3.id
    assert Enum.at(data, 8)["userTrigger"]["trigger"]["id"] == a2.id
  end

  test "get most voted entities with people with sanfam role", context do
    %{conn: conn} = context
    w0 = insert(:watchlist, type: :project, is_public: true)
    s0 = insert(:screener, type: :project, is_public: true)
    i0 = insert(:published_post)
    c0 = insert(:chart_configuration, is_public: true)

    user = insert(:user)

    {:ok, _} =
      Sanbase.Accounts.UserRole.create(user.id, Sanbase.Accounts.Role.san_family_role_id())

    w1 = insert(:watchlist, type: :project, is_public: true, user: user)
    s1 = insert(:screener, type: :project, is_public: true, user: user)
    i1 = insert(:published_post, user: user)
    c1 = insert(:chart_configuration, is_public: true, user: user)

    # Vote for the non-san fam users'entities
    for _ <- 1..4, do: vote(conn, "watchlistId", w0.id)
    for _ <- 1..3, do: vote(conn, "insightId", i0.id)
    for _ <- 1..2, do: vote(conn, "watchlistId", s0.id)
    for _ <- 1..1, do: vote(conn, "chartConfigurationId", c0.id)

    # Vote for the non-san fam users' entities
    for _ <- 1..4, do: vote(conn, "watchlistId", w1.id)
    for _ <- 1..3, do: vote(conn, "insightId", i1.id)
    for _ <- 1..2, do: vote(conn, "watchlistId", s1.id)
    for _ <- 1..1, do: vote(conn, "chartConfigurationId", c1.id)

    result =
      get_most_voted(
        conn,
        [:screener, :insight, :chart_configuration, :project_watchlist],
        user_role_data_only: :san_family
      )

    data = result["data"]
    stats = result["stats"]

    # Expect: w1, i1, c1, a1
    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == w1.id
    assert Enum.at(data, 1)["insight"]["id"] == i1.id
    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() == s1.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == c1.id
  end

  test "get most voted featured entities", context do
    %{conn: conn} = context
    w1 = insert(:watchlist, type: :project, is_public: true)
    s1 = insert(:screener, type: :project, is_public: true)
    i1 = insert(:published_post)
    i2 = insert(:published_post)
    c1 = insert(:chart_configuration, is_public: true)
    c2 = insert(:chart_configuration, is_public: true)

    :ok = Sanbase.FeaturedItem.update_item(w1, true)
    :ok = Sanbase.FeaturedItem.update_item(i2, true)
    :ok = Sanbase.FeaturedItem.update_item(c2, true)

    for _ <- 1..8, do: vote(conn, "watchlistId", w1.id)
    for _ <- 1..7, do: vote(conn, "watchlistId", s1.id)
    for _ <- 1..6, do: vote(conn, "chartConfigurationId", c1.id)
    for _ <- 1..6, do: vote(conn, "chartConfigurationId", c2.id)
    for _ <- 1..4, do: vote(conn, "insightId", i1.id)
    for _ <- 1..4, do: vote(conn, "insightId", i2.id)

    result =
      get_most_voted(
        conn,
        [:screener, :insight, :chart_configuration, :project_watchlist],
        is_featured_data_only: true
      )

    data = result["data"]
    stats = result["stats"]

    # Expect: w1, i1, c1, a1
    assert %{
             "totalEntitiesCount" => 3,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == w1.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c2.id
    assert Enum.at(data, 2)["insight"]["id"] == i2.id
  end

  defp create_alert(user, project) do
    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    {:ok, created_trigger} =
      Sanbase.Alert.UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings
      })

    created_trigger
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

  # Get the most voted entity. Filter only those created in the last 7 days
  defp get_most_voted(conn, entity_or_entities, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:page, 1)
      |> Keyword.put_new(:page_size, 10)
      |> Keyword.put_new(:types, List.wrap(entity_or_entities))
      |> Keyword.put_new(:cursor, %{
        type: :after,
        datetime: "utc_now-7d",
        map_as_input_object: true
      })

    args =
      case Map.new(opts) do
        %{filter: _} = map -> put_in(map, [:filter, :map_as_input_object], true)
        map -> map
      end

    query = """
    {
      getMostVoted(#{map_to_args(args)}){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
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
