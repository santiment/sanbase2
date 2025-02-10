defmodule SanbaseWeb.Graphql.GetMostUsedApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  # Note: There cannot be more than 1 interaction for the same user, type and entity
  # in a predefined time window. This option is disabled in test env by adding
  # `config :sanbase, Sanbase.Accounts.Interaction, interaction_cooldown_seconds: 0`
  # to test.exs config.

  setup do
    _role = insert(:role_san_family)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  defp create_interaction_api(conn, type, id) do
    mutation = """
    mutation{
      storeUserEntityInteraction(
        entityType: #{type |> to_string() |> String.upcase()}
        entityId: #{id}
        interactionType: VIEW)
    }
    """

    %{"data" => %{"storeUserEntityInteraction" => true}} =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
  end

  test "get most used insights", context do
    %{conn: conn} = context
    insight1 = insert(:published_post)
    _unpublished = insert(:post)
    insight2 = insert(:published_post)
    _unpublished = insert(:post)
    insight3 = insert(:published_post)
    insight4 = insert(:published_post)
    _unused = insert(:published_post)

    for index <- 1..10 do
      if rem(index, 4) == 0, do: create_interaction_api(conn, :insight, insight1.id)
      if rem(index, 3) == 0, do: create_interaction_api(conn, :insight, insight2.id)
      if rem(index, 2) == 0, do: create_interaction_api(conn, :insight, insight3.id)
      if rem(index, 1) == 0, do: create_interaction_api(conn, :insight, insight4.id)
    end

    result = get_most_used(conn, :insight)
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

  test "get most used dashboard", context do
    %{conn: conn} = context
    dashboard1 = insert(:dashboard, is_public: false, user: context.user)
    dashboard2 = insert(:dashboard, is_public: true)
    dashboard3 = insert(:dashboard, is_public: false, user: context.user)
    _unused = insert(:dashboard, is_public: false)
    dashboard4 = insert(:dashboard, is_public: true)
    _unused = insert(:dashboard, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :dashboard, dashboard1.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :dashboard, dashboard4.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :dashboard, dashboard3.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :dashboard, dashboard2.id)
    end

    result = get_most_used(conn, :dashboard)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["dashboard"]["id"] == dashboard2.id
    assert Enum.at(data, 1)["dashboard"]["id"] == dashboard3.id
    assert Enum.at(data, 2)["dashboard"]["id"] == dashboard4.id
    assert Enum.at(data, 3)["dashboard"]["id"] == dashboard1.id
  end

  test "get most used screener", context do
    %{conn: conn} = context
    _not_screener = insert(:watchlist, is_public: true)
    screener1 = insert(:screener, is_public: true)
    screener2 = insert(:screener, is_public: false, user: context.user)
    screener3 = insert(:screener, is_public: true)
    _unused = insert(:screener, is_public: false)
    screener4 = insert(:screener, is_public: false, user: context.user)
    _unused = insert(:screener, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :screener, screener1.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :screener, screener4.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :screener, screener3.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :screener, screener2.id)
    end

    result = get_most_used(conn, :screener)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert String.to_integer(Enum.at(data, 0)["screener"]["id"]) == screener2.id
    assert String.to_integer(Enum.at(data, 1)["screener"]["id"]) == screener3.id
    assert String.to_integer(Enum.at(data, 2)["screener"]["id"]) == screener4.id
    assert String.to_integer(Enum.at(data, 3)["screener"]["id"]) == screener1.id
  end

  test "get most used project watchlist", context do
    %{conn: conn} = context

    # The screener should not be in the result
    w1 = insert(:watchlist, type: :project, is_public: false, user: context.user)
    w2 = insert(:watchlist, type: :project, is_public: true)
    w3 = insert(:watchlist, type: :project, is_public: false, user: context.user)
    _screener = insert(:screener, type: :project, is_public: true)
    w4 = insert(:watchlist, type: :project, is_public: true)
    _unused = insert(:watchlist, type: :project, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :project_watchlist, w2.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :project_watchlist, w3.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :project_watchlist, w1.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :project_watchlist, w4.id)
    end

    result = get_most_used(conn, :project_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert String.to_integer(Enum.at(data, 0)["projectWatchlist"]["id"]) == w4.id
    assert String.to_integer(Enum.at(data, 1)["projectWatchlist"]["id"]) == w1.id
    assert String.to_integer(Enum.at(data, 2)["projectWatchlist"]["id"]) == w3.id
    assert String.to_integer(Enum.at(data, 3)["projectWatchlist"]["id"]) == w2.id
  end

  test "get most used address watchlist", context do
    %{conn: conn} = context

    # The screener should not be in the result
    w1 = insert(:watchlist, type: :blockchain_address, is_public: true)
    w2 = insert(:watchlist, type: :blockchain_address, is_public: false, user: context.user)
    w3 = insert(:watchlist, type: :blockchain_address, is_public: true)
    _screener = insert(:screener, type: :blockchain_address, is_public: true)
    w4 = insert(:watchlist, type: :blockchain_address, is_public: false, user: context.user)
    _unused = insert(:watchlist, type: :blockchain_address, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :address_watchlist, w2.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :address_watchlist, w3.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :address_watchlist, w1.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :address_watchlist, w4.id)
    end

    result = get_most_used(conn, :address_watchlist)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert String.to_integer(Enum.at(data, 0)["addressWatchlist"]["id"]) == w4.id
    assert String.to_integer(Enum.at(data, 1)["addressWatchlist"]["id"]) == w1.id
    assert String.to_integer(Enum.at(data, 2)["addressWatchlist"]["id"]) == w3.id
    assert String.to_integer(Enum.at(data, 3)["addressWatchlist"]["id"]) == w2.id
  end

  test "get most used chart configuration", context do
    %{conn: conn} = context
    c1 = insert(:chart_configuration, is_public: true)
    c2 = insert(:chart_configuration, is_public: false, user: context.user)
    c3 = insert(:chart_configuration, is_public: true)
    c4 = insert(:chart_configuration, is_public: true)
    _unused = insert(:chart_configuration, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :chart_configuration, c2.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :chart_configuration, c1.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :chart_configuration, c4.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :chart_configuration, c3.id)
    end

    result = get_most_used(conn, :chart_configuration)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["chartConfiguration"]["id"] == c3.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c4.id
    assert Enum.at(data, 2)["chartConfiguration"]["id"] == c1.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == c2.id
  end

  test "get most used user trigger", context do
    %{conn: conn} = context

    ut1 = insert(:user_trigger, is_public: false, user: context.user)
    ut2 = insert(:user_trigger, is_public: true)
    ut3 = insert(:user_trigger, is_public: false, user: context.user)
    ut4 = insert(:user_trigger, is_public: true)
    _unused = insert(:user_trigger, is_public: true)

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :user_trigger, ut2.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :user_trigger, ut1.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :user_trigger, ut3.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :user_trigger, ut4.id)
    end

    result = get_most_used(conn, :user_trigger)
    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 4,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 4
    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == ut4.id
    assert Enum.at(data, 1)["userTrigger"]["trigger"]["id"] == ut3.id
    assert Enum.at(data, 2)["userTrigger"]["trigger"]["id"] == ut1.id
    assert Enum.at(data, 3)["userTrigger"]["trigger"]["id"] == ut2.id
  end

  test "get most used combined", context do
    %{conn: conn} = context
    ut = insert(:user_trigger, is_public: false, user: context.user)
    p = insert(:published_post)
    c = insert(:chart_configuration, is_public: true)
    s = insert(:screener, is_public: true)
    w = insert(:watchlist, type: :project, is_public: true)
    d = insert(:dashboard, is_public: true)
    q = insert(:query, is_public: true)

    for i <- 1..20 do
      if rem(i, 7) == 0, do: create_interaction_api(conn, :query, q.id)
      if rem(i, 6) == 0, do: create_interaction_api(conn, :dashboard, d.id)
      if rem(i, 5) == 0, do: create_interaction_api(conn, :user_trigger, ut.id)
      if rem(i, 4) == 0, do: create_interaction_api(conn, :chart_configuration, c.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :project_watchlist, w.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :screener, s.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :insight, p.id)
    end

    # Get with default page = 1 and pageSize = 10, all entities are returned
    result =
      get_most_used(conn, [
        :insight,
        :project_watchlist,
        :screener,
        :chart_configuration,
        :user_trigger,
        :dashboard,
        :query
      ])

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 7,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 7

    assert Enum.at(data, 0)["insight"]["id"] == p.id
    assert String.to_integer(Enum.at(data, 1)["screener"]["id"]) == s.id
    assert String.to_integer(Enum.at(data, 2)["projectWatchlist"]["id"]) == w.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == c.id
    assert Enum.at(data, 4)["userTrigger"]["trigger"]["id"] == ut.id
    assert Enum.at(data, 5)["dashboard"]["id"] == d.id
    assert Enum.at(data, 6)["query"]["id"] == q.id
  end

  test "get most used with projects' slugs filter", context do
    %{conn: conn} = context
    slug = "some_slug"

    to_ids = fn projects -> Enum.map(projects, &%{project_id: &1.id}) end
    # projects
    p1 = insert(:project, slug: slug)
    p2 = insert(:project)

    [w1, w2] =
      for p_list <- [[p2], [p1, p2]] do
        w = insert(:watchlist, type: :project, is_public: true)

        {:ok, w} =
          Sanbase.UserList.update_user_list(context.user, %{id: w.id, list_items: to_ids.(p_list)})

        w
      end

    i1 = insert(:published_post, price_chart_project: p1)
    i2 = insert(:published_post, price_chart_project: p2)

    c1 = insert(:chart_configuration, is_public: true, project: p1)
    c2 = insert(:chart_configuration, is_public: true, project: p2)

    a1 = create_alert(context.user, p1)
    a2 = create_alert(context.user, p2)

    for i <- 1..60 do
      if rem(i, 10) == 0, do: create_interaction_api(conn, :insight, i2.id)
      if rem(i, 7) == 0, do: create_interaction_api(conn, :insight, i1.id)
      if rem(i, 5) == 0, do: create_interaction_api(conn, :user_trigger, a1.id)
      if rem(i, 5) == 0, do: create_interaction_api(conn, :user_trigger, a2.id)
      if rem(i, 4) == 0, do: create_interaction_api(conn, :chart_configuration, c2.id)
      if rem(i, 4) == 0, do: create_interaction_api(conn, :chart_configuration, c1.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :project_watchlist, w1.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :project_watchlist, w2.id)
    end

    result =
      get_most_used(
        conn,
        [:project_watchlist, :insight, :chart_configuration, :user_trigger],
        filter: %{slugs: [p1.slug]}
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

    assert String.to_integer(Enum.at(data, 0)["projectWatchlist"]["id"]) == w2.id
    assert Enum.at(data, 1)["chartConfiguration"]["id"] == c1.id
    assert Enum.at(data, 2)["userTrigger"]["trigger"]["id"] == a1.id
    assert Enum.at(data, 3)["insight"]["id"] == i1.id
  end

  test "get most used screeners with metrics filter", context do
    %{conn: conn} = context

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

      (&Sanbase.Metric.slugs_by_filter/6)
      |> Sanbase.Mock.prepare_mock2({:ok, []})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert Sanbase.WatchlistFunction.valid_function?(function)
      end)

      function
    end

    s1 = insert(:screener, is_public: true, function: function.(["price_usd"]))

    s2 =
      insert(:screener,
        is_public: false,
        function: function.(["social_volume_total"]),
        user: context.user
      )

    s3 = insert(:screener, is_public: true, function: function.(["price_usd", "price_btc"]))
    s4 = insert(:screener, is_public: true, function: function.(["price_usd", "price_btc"]))
    _unused = insert(:screener, is_public: true, function: function.(["price_usd", "price_btc"]))

    for i <- 1..10 do
      if rem(i, 4) == 0, do: create_interaction_api(conn, :screener, s2.id)
      if rem(i, 3) == 0, do: create_interaction_api(conn, :screener, s1.id)
      if rem(i, 2) == 0, do: create_interaction_api(conn, :screener, s3.id)
      if rem(i, 1) == 0, do: create_interaction_api(conn, :screener, s4.id)
    end

    result = get_most_used(conn, [:screener], filter: %{metrics: ["price_usd"]})

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 3,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert String.to_integer(Enum.at(data, 0)["screener"]["id"]) == s4.id
    assert String.to_integer(Enum.at(data, 1)["screener"]["id"]) == s3.id
    assert String.to_integer(Enum.at(data, 2)["screener"]["id"]) == s1.id
  end

  test "get most used featured entities", context do
    %{conn: conn} = context
    w1 = insert(:watchlist, type: :project, is_public: true)
    s1 = insert(:screener, type: :project, is_public: false, user: context.user)
    i1 = insert(:published_post)
    i2 = insert(:published_post)
    c1 = insert(:chart_configuration, is_public: true)
    c2 = insert(:chart_configuration, is_public: false, user: context.user)

    :ok = Sanbase.FeaturedItem.update_item(w1, true)
    :ok = Sanbase.FeaturedItem.update_item(i2, true)
    :ok = Sanbase.FeaturedItem.update_item(c1, true)

    for i <- 1..60 do
      if rem(i, 20) == 0, do: create_interaction_api(conn, :project_watchlist, w1.id)
      if rem(i, 20) == 0, do: create_interaction_api(conn, :screener, s1.id)
      if rem(i, 10) == 0, do: create_interaction_api(conn, :insight, i1.id)
      if rem(i, 10) == 0, do: create_interaction_api(conn, :insight, i2.id)
      if rem(i, 5) == 0, do: create_interaction_api(conn, :chart_configuration, c1.id)
      if rem(i, 5) == 0, do: create_interaction_api(conn, :chart_configuration, c2.id)
    end

    result =
      get_most_used(
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

    assert Enum.at(data, 0)["chartConfiguration"]["id"] == c1.id
    assert Enum.at(data, 1)["insight"]["id"] == i2.id
    assert String.to_integer(Enum.at(data, 2)["projectWatchlist"]["id"]) == w1.id
  end

  defp get_most_used(conn, entity_or_entities, opts \\ []) do
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
      getMostUsed(#{map_to_args(args)}){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
        data {
          insight{ id }
          projectWatchlist{ id }
          addressWatchlist{ id }
          screener{ id }
          chartConfiguration{ id }
          userTrigger{ trigger{ id } }
          dashboard{ id }
          query{ id }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostUsed"])
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
end
