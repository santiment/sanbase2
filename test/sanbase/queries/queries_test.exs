defmodule Sanbase.QueriesTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  alias Sanbase.Queries

  setup do
    user = insert(:user)

    assert {:ok, query} =
             Queries.create_query(
               %{
                 sql_query: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                 sql_parameters: %{"slug" => "ethereum", "limit" => 20}
               },
               user.id
             )

    {:ok, dashboard} = Sanbase.Dashboards.create_dashboard(%{name: "My dashboard"}, user.id)

    %{user: user, query: query, dashboard: dashboard}
  end

  describe "Queries CRUD" do
    test "create", %{user: user} do
      assert {:ok, query} =
               Queries.create_query(
                 %{
                   sql_query: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                   sql_parameters: %{"slug" => "ethereum", "limit" => 20}
                 },
                 user.id
               )

      assert {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert fetched_query.sql_query ==
               "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}"

      assert fetched_query.sql_parameters == %{"slug" => "ethereum", "limit" => 20}

      assert fetched_query.user_id == user.id
      assert fetched_query.id == query.id
      assert fetched_query.uuid == query.uuid
    end

    test "get query", %{user: user, query: query} do
      {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert query.id == fetched_query.id
      assert query.uuid == fetched_query.uuid
      assert query.origin_uuid == fetched_query.origin_uuid
      assert query.sql_query == fetched_query.sql_query
      assert query.sql_parameters == fetched_query.sql_parameters
      assert query.user_id == fetched_query.user_id
      assert query.settings == fetched_query.settings
    end

    test "get dashboard query", %{user: user, dashboard: dashboard, query: query} do
      {:ok, dashboard_query_mapping} =
        Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, %{}, user.id)
    end

    test "can update own query", %{user: user, query: query} do
      assert {:ok, updated_query} =
               Queries.update_query(
                 query.id,
                 user.id,
                 %{
                   name: "My updated dashboard",
                   sql_query: "SELECT * FROM metrics WHERE slug IN {{slugs}}",
                   sql_parameters: %{"slugs" => ["ethereum", "bitcoin"]}
                 }
               )

      # The returned result is updated
      assert updated_query.id == query.id
      assert updated_query.name == "My updated dashboard"
      assert updated_query.sql_query == "SELECT * FROM metrics WHERE slug IN {{slugs}}"
      assert updated_query.sql_parameters == %{"slugs" => ["ethereum", "bitcoin"]}

      # The updates are persisted
      assert {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert fetched_query.id == query.id
      assert fetched_query.name == "My updated dashboard"
      assert fetched_query.sql_query == "SELECT * FROM metrics WHERE slug IN {{slugs}}"
      assert fetched_query.sql_parameters == %{"slugs" => ["ethereum", "bitcoin"]}
    end

    test "cannot update other user query", %{query: query} do
      user2 = insert(:user)

      assert {:error, error_msg} =
               Queries.update_query(
                 query.id,
                 user2.id,
                 %{
                   name: "My updated dashboard",
                   sql_query: "SELECT * FROM metrics WHERE slug IN {{slugs}}",
                   sql_parameters: %{"slugs" => ["ethereum", "bitcoin"]}
                 }
               )

      assert error_msg =~ "does not exist or it belongs to another user"
    end

    test "get all user queries", %{user: user, query: query} do
      assert {:ok, query2} = Queries.create_query(%{}, user.id)
      assert {:ok, query3} = Queries.create_query(%{}, user.id)
      assert {:ok, list} = Queries.get_user_queries(user.id, user.id, page: 1, page_size: 10)

      assert length(list) == 3

      assert Enum.map(list, & &1.id) |> Enum.sort() ==
               [query.id, query2.id, query3.id] |> Enum.sort()
    end
  end
end
