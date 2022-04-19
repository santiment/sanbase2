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
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["insight"]["id"] == insight4.id
    assert Enum.at(data, 1)["insight"]["id"] == insight3.id
    assert Enum.at(data, 2)["insight"]["id"] == insight2.id
    assert Enum.at(data, 3)["insight"]["id"] == insight1.id
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
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() == screener4.id
    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() == screener3.id
    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() == screener2.id
    assert Enum.at(data, 3)["screener"]["id"] |> String.to_integer() == screener1.id
  end

  test "get most recent project watchlist", %{conn: conn} do
    # The screener should not be in the result
    watchlist1 = insert(:watchlist, type: :project, is_public: true, inserted_at: seconds_ago(30))
    _private = insert(:watchlist, type: :project, is_public: false, inserted_at: seconds_ago(25))
    _private = insert(:watchlist, type: :project, is_public: false, inserted_at: seconds_ago(20))
    watchlist2 = insert(:watchlist, type: :project, is_public: true, inserted_at: seconds_ago(15))
    watchlist3 = insert(:watchlist, type: :project, is_public: true, inserted_at: seconds_ago(10))
    _screener = insert(:screener, type: :project, is_public: true, inserted_at: seconds_ago(5))
    watchlist4 = insert(:watchlist, type: :project, is_public: true, inserted_at: seconds_ago(0))

    result = get_most_recent(conn, :project_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(data, 2)["projectWatchlist"]["id"] |> String.to_integer() == watchlist2.id
    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() == watchlist1.id
  end

  test "get most recent address watchlist", %{conn: conn} do
    make_opts = fn is_public, seconds_ago ->
      [type: :blockchain_address, is_public: is_public, inserted_at: seconds_ago(seconds_ago)]
    end

    # The screener should not be in the result
    watchlist1 = insert(:watchlist, make_opts.(true, 30))
    _private = insert(:watchlist, make_opts.(false, 25))
    _private = insert(:watchlist, make_opts.(false, 20))
    watchlist2 = insert(:watchlist, make_opts.(true, 15))
    watchlist3 = insert(:watchlist, make_opts.(true, 10))
    _screener = insert(:screener, make_opts.(true, 5))
    watchlist4 = insert(:watchlist, make_opts.(true, 0))

    result = get_most_recent(conn, :address_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(data, 1)["addressWatchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(data, 2)["addressWatchlist"]["id"] |> String.to_integer() == watchlist2.id
    assert Enum.at(data, 3)["addressWatchlist"]["id"] |> String.to_integer() == watchlist1.id
  end

  test "get most recent chart configuration", %{conn: conn} do
    chart_configuration1 = insert(:chart_configuration, is_public: true)
    chart_configuration2 = insert(:chart_configuration, is_public: true)
    _private = insert(:chart_configuration, is_public: false)
    _private = insert(:chart_configuration, is_public: false)
    chart_configuration3 = insert(:chart_configuration, is_public: true)
    chart_configuration4 = insert(:chart_configuration, is_public: true)

    result = get_most_recent(conn, :chart_configuration)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["chartConfiguration"]["id"] == chart_configuration4.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == chart_configuration3.id
    assert Enum.at(data, 2)["chartConfiguration"]["id"] == chart_configuration2.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == chart_configuration1.id
  end

  test "get most recent user trigger", %{conn: conn} do
    user_trigger1 = insert(:user_trigger, is_public: true)
    user_trigger2 = insert(:user_trigger, is_public: true)
    _private = insert(:user_trigger, is_public: false)
    _private = insert(:user_trigger, is_public: false)
    user_trigger3 = insert(:user_trigger, is_public: true)
    user_trigger4 = insert(:user_trigger, is_public: true)

    result = get_most_recent(conn, :user_trigger)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == user_trigger4.id
    assert Enum.at(data, 1)["userTrigger"]["trigger"]["id"] == user_trigger3.id
    assert Enum.at(data, 2)["userTrigger"]["trigger"]["id"] == user_trigger2.id
    assert Enum.at(data, 3)["userTrigger"]["trigger"]["id"] == user_trigger1.id
  end

  test "get most recent combined", %{conn: conn} do
    user_trigger = insert(:user_trigger, is_public: true, inserted_at: seconds_ago(55))
    insight1 = insert(:published_post, published_at: seconds_ago(50))
    conf1 = insert(:chart_configuration, is_public: true, inserted_at: seconds_ago(45))
    insight2 = insert(:published_post, published_at: seconds_ago(40))
    conf2 = insert(:chart_configuration, is_public: true, inserted_at: seconds_ago(35))
    screener = insert(:screener, is_public: true, inserted_at: seconds_ago(30))

    project_watchlist =
      insert(:watchlist, type: :project, is_public: true, inserted_at: seconds_ago(20))

    address_watchlist =
      insert(:watchlist, type: :blockchain_address, is_public: true, inserted_at: seconds_ago(20))

    # Get with default page = 1 and pageSize = 10, all entities are returned
    result =
      get_most_recent(conn, [
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
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 8

    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() ==
             address_watchlist.id

    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() ==
             project_watchlist.id

    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() == screener.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == conf2.id
    assert Enum.at(data, 4)["insight"]["id"] == insight2.id
    assert Enum.at(data, 5)["chartConfiguration"]["id"] == conf1.id
    assert Enum.at(data, 6)["insight"]["id"] == insight1.id
    assert Enum.at(data, 7)["userTrigger"]["trigger"]["id"] == user_trigger.id

    # Get with default page = 3 and pageSize = 2, only some entities are returned
    result =
      get_most_recent(
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
             "totalPagesCount" => 4,
             "currentPageSize" => 2
           } = stats

    assert Enum.at(data, 0)["insight"]["id"] == insight2.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == conf1.id
  end

  test "get most recent with projects' slugs filter", context do
    to_ids = fn projects -> Enum.map(projects, &%{project_id: &1.id}) end
    # projects
    pl = [p1, p2, p3, p4] = for slug <- ["p1", "p2", "p3", "p4"], do: insert(:project, slug: slug)

    offset = 40

    [w1, w2, w3, _w4] =
      for {p_list, index} <- Enum.with_index([[p1, p2, p3], [p2, p3], [p3, p4], [p4]], 1) do
        w =
          insert(:watchlist,
            type: :project,
            is_public: true,
            inserted_at: seconds_ago(offset - index)
          )

        {:ok, w} =
          Sanbase.UserList.update_user_list(context.user, %{id: w.id, list_items: to_ids.(p_list)})

        w
      end

    pl_index = Enum.with_index(pl, 1)

    offset = 30

    [i1, i2, i3, _i4] =
      for {p, index} <- pl_index do
        insert(:published_post,
          price_chart_project: p,
          published_at: seconds_ago(offset - index)
        )
      end

    offset = 20

    [c1, c2, c3, _c4] =
      for {p, index} <- pl_index do
        insert(:chart_configuration,
          is_public: true,
          project: p,
          inserted_at: seconds_ago(offset - index)
        )
      end

    offset = 10

    [a1, a2, a3, _a4] =
      for {p, index} <- pl_index do
        create_alert(context.user, p, seconds_ago(offset - index))
      end

    result =
      get_most_recent(
        context.conn,
        [:project_watchlist, :insight, :chart_configuration, :user_trigger],
        filter: %{slugs: [p1.slug]}
      )

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == a1.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c1.id
    assert Enum.at(data, 2)["insight"]["id"] == i1.id
    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() == w1.id

    result =
      get_most_recent(
        context.conn,
        [:project_watchlist, :insight, :chart_configuration, :user_trigger],
        filter: %{slugs: [p2.slug, p3.slug]}
      )

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 9,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == a3.id
    assert Enum.at(data, 1)["userTrigger"]["trigger"]["id"] == a2.id
    assert Enum.at(data, 2)["chartConfiguration"]["id"] == c3.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == c2.id
    assert Enum.at(data, 4)["insight"]["id"] == i3.id
    assert Enum.at(data, 5)["insight"]["id"] == i2.id
    assert Enum.at(data, 6)["projectWatchlist"]["id"] |> String.to_integer() == w3.id
    assert Enum.at(data, 7)["projectWatchlist"]["id"] |> String.to_integer() == w2.id
    assert Enum.at(data, 8)["projectWatchlist"]["id"] |> String.to_integer() == w1.id
  end

  defp create_alert(user, project, inserted_at) do
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

    naive_dt = DateTime.to_naive(inserted_at) |> NaiveDateTime.truncate(:second)

    created_trigger =
      created_trigger
      |> Ecto.Changeset.change(%{inserted_at: naive_dt})
      |> Sanbase.Repo.update!()

    created_trigger
  end

  defp get_most_recent(conn, entity_or_entities, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)

    types_str =
      case entity_or_entities do
        [_ | _] = types ->
          types =
            Enum.map(types, &(&1 |> Atom.to_string() |> String.upcase()))
            |> Enum.join(", ")

          "types: [#{types}]"

        type when is_atom(type) ->
          "type: #{type |> Atom.to_string() |> String.upcase()}"
      end

    filter_str =
      case Keyword.get(opts, :filter, nil) do
        nil -> ""
        filter -> "filter: #{map_to_input_object_str(filter)}"
      end

    query = """
    {
      getMostRecent(
        #{types_str}
        page: #{page}
        pageSize: #{page_size}
        #{filter_str}
      ){
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
    |> get_in(["data", "getMostRecent"])
  end
end
