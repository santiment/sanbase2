defmodule SanbaseWeb.Graphql.GetMostUsedApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Accounts.Activity

  setup do
    _role = insert(:role_san_family)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  defp create_activity(user_id, type, id) do
    {:ok, _} = Activity.store_user_activity(user_id, %{entity_type: type, entity_id: id})
  end

  test "get most used insights", context do
    %{conn: conn, user: user} = context
    insight1 = insert(:published_post)
    _unpublished = insert(:post)
    insight2 = insert(:published_post)
    _unpublished = insert(:post)
    insight3 = insert(:published_post)
    insight4 = insert(:published_post)
    _unused = insert(:published_post)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :insight, insight1.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :insight, insight2.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :insight, insight3.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :insight, insight4.id)
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

  test "get most used screener", context do
    %{conn: conn, user: user} = context
    _not_screener = insert(:watchlist, is_public: true)
    screener1 = insert(:screener, is_public: true)
    screener2 = insert(:screener, is_public: true)
    screener3 = insert(:screener, is_public: true)
    _private = insert(:screener, is_public: false)
    _private = insert(:screener, is_public: false)
    screener4 = insert(:screener, is_public: true)
    _unused = insert(:screener, is_public: true)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :watchlist, screener1.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :watchlist, screener4.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :watchlist, screener3.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :watchlist, screener2.id)
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
    assert Enum.at(data, 0)["screener"]["id"] |> String.to_integer() == screener2.id
    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() == screener3.id
    assert Enum.at(data, 2)["screener"]["id"] |> String.to_integer() == screener4.id
    assert Enum.at(data, 3)["screener"]["id"] |> String.to_integer() == screener1.id
  end

  test "get most recent project watchlist", context do
    %{conn: conn, user: user} = context

    # The screener should not be in the result
    watchlist1 = insert(:watchlist, type: :project, is_public: true)
    _private = insert(:watchlist, type: :project, is_public: false)
    _private = insert(:watchlist, type: :project, is_public: false)
    watchlist2 = insert(:watchlist, type: :project, is_public: true)
    watchlist3 = insert(:watchlist, type: :project, is_public: true)
    _screener = insert(:screener, type: :project, is_public: true)
    watchlist4 = insert(:watchlist, type: :project, is_public: true)
    _unused = insert(:watchlist, type: :project, is_public: true)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :watchlist, watchlist2.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :watchlist, watchlist3.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :watchlist, watchlist1.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :watchlist, watchlist4.id)
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
    assert Enum.at(data, 0)["projectWatchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(data, 1)["projectWatchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(data, 2)["projectWatchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(data, 3)["projectWatchlist"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most recent address watchlist", context do
    %{conn: conn, user: user} = context

    # The screener should not be in the result
    watchlist1 = insert(:watchlist, type: :blockchain_address, is_public: true)
    _private = insert(:watchlist, type: :blockchain_address, is_public: false)
    _private = insert(:watchlist, type: :blockchain_address, is_public: false)
    watchlist2 = insert(:watchlist, type: :blockchain_address, is_public: true)
    watchlist3 = insert(:watchlist, type: :blockchain_address, is_public: true)
    _screener = insert(:screener, type: :blockchain_address, is_public: true)
    watchlist4 = insert(:watchlist, type: :blockchain_address, is_public: true)
    _unused = insert(:watchlist, type: :blockchain_address, is_public: true)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :watchlist, watchlist2.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :watchlist, watchlist3.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :watchlist, watchlist1.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :watchlist, watchlist4.id)
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
    assert Enum.at(data, 0)["addressWatchlist"]["id"] |> String.to_integer() == watchlist4.id
    assert Enum.at(data, 1)["addressWatchlist"]["id"] |> String.to_integer() == watchlist1.id
    assert Enum.at(data, 2)["addressWatchlist"]["id"] |> String.to_integer() == watchlist3.id
    assert Enum.at(data, 3)["addressWatchlist"]["id"] |> String.to_integer() == watchlist2.id
  end

  test "get most recent chart configuration", context do
    %{conn: conn, user: user} = context
    c1 = insert(:chart_configuration, is_public: true)
    c2 = insert(:chart_configuration, is_public: true)
    _private = insert(:chart_configuration, is_public: false)
    _private = insert(:chart_configuration, is_public: false)
    c3 = insert(:chart_configuration, is_public: true)
    c4 = insert(:chart_configuration, is_public: true)
    _unused = insert(:chart_configuration, is_public: true)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :chart_configuration, c2.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :chart_configuration, c1.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :chart_configuration, c4.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :chart_configuration, c3.id)
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

  test "get most recent user trigger", context do
    %{conn: conn, user: user} = context

    user_trigger1 = insert(:user_trigger, is_public: true)
    user_trigger2 = insert(:user_trigger, is_public: true)
    _private = insert(:user_trigger, is_public: false)
    _private = insert(:user_trigger, is_public: false)
    user_trigger3 = insert(:user_trigger, is_public: true)
    user_trigger4 = insert(:user_trigger, is_public: true)
    _unused = insert(:user_trigger, is_public: true)

    for index <- 1..50 do
      if rem(index, 5) == 0, do: create_activity(user.id, :user_trigger, user_trigger2.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :user_trigger, user_trigger1.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :user_trigger, user_trigger3.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :user_trigger, user_trigger4.id)
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
    assert Enum.at(data, 0)["userTrigger"]["trigger"]["id"] == user_trigger4.id
    assert Enum.at(data, 1)["userTrigger"]["trigger"]["id"] == user_trigger3.id
    assert Enum.at(data, 2)["userTrigger"]["trigger"]["id"] == user_trigger1.id
    assert Enum.at(data, 3)["userTrigger"]["trigger"]["id"] == user_trigger2.id
  end

  test "get most recent combined", context do
    %{conn: conn, user: user} = context
    ut = insert(:user_trigger, user: user, is_public: true)
    i = insert(:published_post, user: user)
    c = insert(:chart_configuration, user: user, is_public: true)
    s = insert(:screener, user: user, is_public: true)
    w = insert(:watchlist, user: user, type: :project, is_public: true)

    for index <- 1..50 do
      if rem(index, 6) == 0, do: create_activity(user.id, :user_trigger, ut.id)
      if rem(index, 5) == 0, do: create_activity(user.id, :chart_configuration, c.id)
      if rem(index, 4) == 0, do: create_activity(user.id, :watchlist, w.id)
      if rem(index, 3) == 0, do: create_activity(user.id, :watchlist, s.id)
      if rem(index, 2) == 0, do: create_activity(user.id, :insight, i.id)
    end

    # Get with default page = 1 and pageSize = 10, all entities are returned
    result =
      get_most_used(conn, [
        :insight,
        :project_watchlist,
        :screener,
        :chart_configuration,
        :user_trigger
      ])

    data = result["data"]
    stats = result["stats"]

    assert %{
             "totalEntitiesCount" => 5,
             "currentPage" => 1,
             "totalPagesCount" => 1,
             "currentPageSize" => 10
           } = stats

    assert length(data) == 5

    assert Enum.at(data, 0)["insight"]["id"] == i.id
    assert Enum.at(data, 1)["screener"]["id"] |> String.to_integer() == s.id
    assert Enum.at(data, 2)["projectWatchlist"]["id"] |> String.to_integer() == w.id
    assert Enum.at(data, 3)["chartConfiguration"]["id"] == c.id
    assert Enum.at(data, 4)["userTrigger"]["trigger"]["id"] == ut.id
  end

  defp get_most_used(conn, entity_or_entities, opts \\ []) do
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

    user_role_data_only_str =
      case Keyword.get(opts, :user_role_data_only) do
        nil -> ""
        role -> "userRoleDataOnly: #{Atom.to_string(role) |> String.upcase()}"
      end

    query = """
    {
      getMostUsed(
        #{types_str}
        page: #{page}
        pageSize: #{page_size}
        #{filter_str}
        #{user_role_data_only_str}
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
    |> get_in(["data", "getMostUsed"])
  end
end
