defmodule SanbaseWeb.Graphql.WatchlistSettingsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    conn = setup_jwt_auth(build_conn(), insert(:user))
    conn2 = setup_jwt_auth(build_conn(), insert(:user))

    {:ok, conn: conn, conn2: conn2}
  end

  test "default watchlist settings", %{conn: conn} do
    %{"id" => watchlist_id} = create_watchlist(conn, title: rand_str())

    settings = get_watchlist_settings(conn, watchlist_id)
    assert settings == %{"pageSize" => 20, "timeWindow" => "180d", "tableColumns" => %{}}
  end

  test "cannot fetch settings of not own private watchlist", %{conn: conn, conn2: conn2} do
    %{"id" => watchlist_id} = create_watchlist(conn, title: rand_str(), is_public: false)

    settings = get_watchlist_settings(conn2, watchlist_id)
    assert settings == nil
  end

  test "use watchlist creator's settings if current user does not have any", %{
    conn: conn,
    conn2: conn2
  } do
    %{"id" => watchlist_id} = create_watchlist(conn, title: rand_str(), is_public: true)

    update_watchlist_settings(conn, watchlist_id,
      page_size: 50,
      time_window: "60d",
      table_columns: %{shown_columns: [1, 2, 3]}
    )

    settings = get_watchlist_settings(conn2, watchlist_id)

    assert settings == %{
             "pageSize" => 50,
             "tableColumns" => %{"shown_columns" => [1, 2, 3]},
             "timeWindow" => "60d"
           }
  end

  test "use own watchlist settings even if the creator has settings", %{
    conn: conn,
    conn2: conn2
  } do
    %{"id" => watchlist_id} = create_watchlist(conn, title: rand_str(), is_public: true)

    update_watchlist_settings(conn2, watchlist_id,
      page_size: 10,
      time_window: "30d",
      table_columns: %{shown_columns: [2, 3]}
    )

    update_watchlist_settings(conn, watchlist_id,
      page_size: 50,
      time_window: "60d",
      table_columns: %{shown_columns: [1, 2, 3]}
    )

    settings = get_watchlist_settings(conn2, watchlist_id)

    assert settings == %{
             "pageSize" => 10,
             "tableColumns" => %{"shown_columns" => [2, 3]},
             "timeWindow" => "30d"
           }
  end

  test "update watchlist for the same user", %{conn: conn} do
    %{"id" => watchlist_id} = create_watchlist(conn, title: rand_str())

    updated_settings =
      update_watchlist_settings(conn, watchlist_id,
        page_size: 20,
        time_window: "180d",
        table_columns: %{}
      )

    watchlist_settings = get_watchlist_settings(conn, watchlist_id)
    # default settings
    assert updated_settings == %{"pageSize" => 20, "timeWindow" => "180d", "tableColumns" => %{}}
    assert updated_settings == watchlist_settings
  end

  defp create_watchlist(conn, opts) do
    mutation = """
    mutation {
      createWatchlist(name: "#{Keyword.get(opts, :title)}", color: BLACK, isPublic: #{
      Keyword.get(opts, :is_public, false)
    }) {
         id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)

    result["data"]["createWatchlist"]
  end

  defp get_watchlist_settings(conn, watchlist_id) do
    query = """
    {
      watchlist(id: #{watchlist_id}) {
         settings{
           pageSize
           tableColumns
           timeWindow
         }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    result["data"]["watchlist"]["settings"]
  end

  defp update_watchlist_settings(conn, watchlist_id, opts) do
    mutation =
      ~s|
      mutation {
        updateWatchlistSettings(
          id: #{watchlist_id},
          settings: {
            pageSize: #{Keyword.get(opts, :page_size)}
            timeWindow: '#{Keyword.get(opts, :time_window)}'
            tableColumns: '#{Keyword.get(opts, :table_columns) |> Jason.encode!()}'
          }) {
            pageSize
            tableColumns
            timeWindow
          }
      }
      |
      |> String.replace(~r|\"|, ~S|\\"|)
      |> String.replace(~r|'|, ~S|"|)

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)

    result["data"]["updateWatchlistSettings"]
  end
end
