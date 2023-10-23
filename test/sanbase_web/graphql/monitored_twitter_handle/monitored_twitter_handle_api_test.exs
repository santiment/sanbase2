defmodule SanbaseWeb.Graphql.MonitoredTwitterHandleApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    [conn: conn]
  end

  test "add twitter handle to monitor", %{conn: conn} do
    # Not monitored
    boolean =
      is_twitter_handle_monitored(conn, %{twitter_handle: "santimentfeed"})
      |> get_in(["data", "isTwitterHandleMonitored"])

    assert boolean == false

    # Monitor the handle, check that the operation succeeds
    result =
      add_twitter_handle_to_monitor(conn, %{twitter_handle: "santimentfeed", notes: "note"})
      |> get_in(["data", "addTwitterHandleToMonitor"])

    assert result == true

    # Now it's monitored
    boolean =
      is_twitter_handle_monitored(conn, %{twitter_handle: "santimentfeed"})
      |> get_in(["data", "isTwitterHandleMonitored"])

    assert boolean == true

    # Trying to add it again fails with an error
    error_msg =
      add_twitter_handle_to_monitor(conn, %{twitter_handle: "santimentfeed", notes: "note"})
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~ "already being monitored"

    # Get current user added handles
    handles =
      get_current_user_handles(conn)
      |> get_in(["data", "getCurrentUserSubmittedTwitterHandles"])

    assert handles == [%{"handle" => "santimentfeed", "notes" => "note"}]
  end

  defp add_twitter_handle_to_monitor(conn, args) do
    mutation = "mutation{ addTwitterHandleToMonitor(#{map_to_args(args)}) }"

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp is_twitter_handle_monitored(conn, args) do
    query = "{ isTwitterHandleMonitored(#{map_to_args(args)}) }"

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_current_user_handles(conn) do
    query = """
    {
      getCurrentUserSubmittedTwitterHandles {
        notes
        handle
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
