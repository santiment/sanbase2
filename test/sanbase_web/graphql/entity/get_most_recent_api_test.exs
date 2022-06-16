defmodule SanbaseWeb.Graphql.GetMostRecentApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    _role = insert(:role_san_family)

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

    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() ==
             screener4.id

    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() ==
             screener3.id

    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() ==
             screener2.id

    assert Enum.at(data, 3)["screener"]["id"] |> String.to_integer() ==
             screener1.id
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
      [
        type: :blockchain_address,
        is_public: is_public,
        inserted_at: seconds_ago(seconds_ago)
      ]
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

  test "get most recent dashboard", %{conn: conn} do
    dashboard1 = insert(:dashboard, is_public: true)
    dashboard2 = insert(:dashboard, is_public: true)
    _private = insert(:dashboard, is_public: false)
    _private = insert(:dashboard, is_public: false)
    dashboard3 = insert(:dashboard, is_public: true)
    dashboard4 = insert(:dashboard, is_public: true)

    result = get_most_recent(conn, :dashboard)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["dashboard"]["id"] == dashboard4.id
    assert Enum.at(data, 1)["dashboard"]["id"] == dashboard3.id
    assert Enum.at(data, 2)["dashboard"]["id"] == dashboard2.id
    assert Enum.at(data, 3)["dashboard"]["id"] == dashboard1.id
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
    dashboard = insert(:dashboard, is_public: true, inserted_at: seconds_ago(60))
    user_trigger = insert(:user_trigger, is_public: true, inserted_at: seconds_ago(55))
    insight1 = insert(:published_post, published_at: seconds_ago(50))
    conf1 = insert(:chart_configuration, is_public: true, inserted_at: seconds_ago(45))
    insight2 = insert(:published_post, published_at: seconds_ago(40))
    conf2 = insert(:chart_configuration, is_public: true, inserted_at: seconds_ago(35))
    screener = insert(:screener, is_public: true, inserted_at: seconds_ago(30))

    project_watchlist =
      insert(:watchlist,
        type: :project,
        is_public: true,
        inserted_at: seconds_ago(20)
      )

    address_watchlist =
      insert(:watchlist,
        type: :blockchain_address,
        is_public: true,
        inserted_at: seconds_ago(20)
      )

    # Get with default page = 1 and pageSize = 10, all entities are returned
    result =
      get_most_recent(conn, [
        :insight,
        :project_watchlist,
        :address_watchlist,
        :screener,
        :chart_configuration,
        :user_trigger,
        :dashboard
      ])

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 9,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 9

    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() ==
             address_watchlist.id

    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() ==
             project_watchlist.id

    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() ==
             screener.id

    assert Enum.at(data, 3)["chartConfiguration"]["id"] == conf2.id
    assert Enum.at(data, 4)["insight"]["id"] == insight2.id
    assert Enum.at(data, 5)["chartConfiguration"]["id"] == conf1.id
    assert Enum.at(data, 6)["insight"]["id"] == insight1.id
    assert Enum.at(data, 7)["userTrigger"]["trigger"]["id"] == user_trigger.id
    assert Enum.at(data, 8)["dashboard"]["id"] == dashboard.id

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
      for {p_list, index} <-
            Enum.with_index([[p1, p2, p3], [p2, p3], [p3, p4], [p4]], 1) do
        w =
          insert(:watchlist,
            type: :project,
            is_public: true,
            inserted_at: seconds_ago(offset - index)
          )

        {:ok, w} =
          Sanbase.UserList.update_user_list(context.user, %{
            id: w.id,
            list_items: to_ids.(p_list)
          })

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

    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() ==
             w1.id

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

    assert Enum.at(data, 6)["projectWatchlist"]["id"] |> String.to_integer() ==
             w3.id

    assert Enum.at(data, 7)["projectWatchlist"]["id"] |> String.to_integer() ==
             w2.id

    assert Enum.at(data, 8)["projectWatchlist"]["id"] |> String.to_integer() ==
             w1.id
  end

  test "get most recent screeners with metrics filter", context do
    function = fn metrics ->
      function = %Sanbase.WatchlistFunction{
        name: "selector",
        args: %{
          filters:
            Enum.map(metrics, fn metric ->
              %{
                metric: metric,
                dynamic_from: "1d",
                dynamic_to: "now",
                operator: :greater_than,
                threshold: 10,
                aggregation: :last
              }
            end)
        }
      }

      Sanbase.Mock.prepare_mock2(&Sanbase.Metric.slugs_by_filter/6, {:ok, []})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert Sanbase.WatchlistFunction.valid_function?(function)
      end)

      function
    end

    s1 =
      insert(:screener,
        is_public: true,
        function: function.(["price_usd"]),
        inserted_at: seconds_ago(30)
      )

    _s2 =
      insert(:screener,
        is_public: true,
        function: function.(["social_volume_total"]),
        inserted_at: seconds_ago(20)
      )

    s3 =
      insert(:screener,
        is_public: true,
        function: function.(["price_usd", "price_btc"]),
        inserted_at: seconds_ago(10)
      )

    result = get_most_recent(context.conn, [:screener], filter: %{metrics: ["price_usd"]})

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 2,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() == s3.id
    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() == s1.id
  end

  test "get most recent entities with people with sanfam role", context do
    %{conn: conn} = context
    _ = insert(:watchlist, type: :project, is_public: true)
    _ = insert(:screener, type: :project, is_public: true)
    _ = insert(:published_post)
    _ = insert(:chart_configuration, is_public: true)
    _ = insert(:dashboard, is_public: true)

    user = insert(:user)

    {:ok, _} =
      Sanbase.Accounts.UserRole.create(
        user.id,
        Sanbase.Accounts.Role.san_family_role_id()
      )

    w =
      insert(:watchlist,
        type: :project,
        is_public: true,
        user: user,
        inserted_at: seconds_ago(30)
      )

    s =
      insert(:screener,
        type: :project,
        is_public: true,
        user: user,
        inserted_at: seconds_ago(25)
      )

    i = insert(:published_post, user: user, published_at: seconds_ago(20))

    c =
      insert(:chart_configuration,
        is_public: true,
        user: user,
        inserted_at: seconds_ago(15)
      )

    d =
      insert(:dashboard,
        is_public: true,
        user: user,
        inserted_at: seconds_ago(10)
      )

    result =
      get_most_recent(
        conn,
        [
          :screener,
          :insight,
          :chart_configuration,
          :project_watchlist,
          :dashboard
        ],
        user_role_data_only: :san_family
      )

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 5,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert Enum.at(data, 0)["dashboard"]["id"] == d.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c.id
    assert Enum.at(data, 2)["insight"]["id"] == i.id
    assert Enum.at(data, 3)["screener"]["id"] |> String.to_integer() == s.id

    assert Enum.at(data, 4)["projectWatchlist"]["id"] |> String.to_integer() ==
             w.id
  end

  test "get most recent featured entities", context do
    %{conn: conn} = context

    w =
      insert(:watchlist,
        type: :project,
        is_public: true,
        inserted_at: seconds_ago(30)
      )

    _ = insert(:screener, type: :project, is_public: true)
    i = insert(:published_post, published_at: seconds_ago(25))
    _ = insert(:published_post)
    _ = insert(:chart_configuration, is_public: true)

    c = insert(:chart_configuration, is_public: true, inserted_at: seconds_ago(20))

    _ = insert(:dashboard, is_public: true)
    d = insert(:dashboard, is_public: true, inserted_at: seconds_ago(15))

    :ok = Sanbase.FeaturedItem.update_item(w, true)
    :ok = Sanbase.FeaturedItem.update_item(i, true)
    :ok = Sanbase.FeaturedItem.update_item(c, true)
    :ok = Sanbase.FeaturedItem.update_item(d, true)

    result =
      get_most_recent(
        conn,
        [
          :screener,
          :insight,
          :chart_configuration,
          :project_watchlist,
          :dashboard
        ],
        is_featured_data_only: true
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

    assert Enum.at(data, 0)["dashboard"]["id"] == d.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c.id
    assert Enum.at(data, 2)["insight"]["id"] == i.id

    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() ==
             w.id
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
    opts =
      opts
      |> Keyword.put_new(:page, 1)
      |> Keyword.put_new(:page_size, 10)
      |> Keyword.put_new(:types, List.wrap(entity_or_entities))

    args =
      case Map.new(opts) do
        %{filter: _} = map -> put_in(map, [:filter, :map_as_input_object], true)
        map -> map
      end

    query = """
    {
      getMostRecent(#{map_to_args(args)}){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
        data {
          addressWatchlist{ id }
          chartConfiguration{ id }
          dashboard{ id }
          insight{ id }
          projectWatchlist{ id }
          screener{ id }
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
