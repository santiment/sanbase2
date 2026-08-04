defmodule SanbaseWeb.Graphql.UserApiCallDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn}
  end

  test "api call data module returns data", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-02 00:00:00Z]
    dt3 = ~U[2019-01-03 00:00:00Z]

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: dt1, api_calls_count: 400},
           %{datetime: dt2, api_calls_count: 100},
           %{datetime: dt3, api_calls_count: 200}
         ]}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          dt1,
          dt3,
          "1d"
        )

      expected_result = %{
        "data" => %{
          "currentUser" => %{
            "apiCallsHistory" => [
              %{
                "apiCallsCount" => 400,
                "datetime" => "2019-01-01T00:00:00Z"
              },
              %{
                "apiCallsCount" => 100,
                "datetime" => "2019-01-02T00:00:00Z"
              },
              %{
                "apiCallsCount" => 200,
                "datetime" => "2019-01-03T00:00:00Z"
              }
            ]
          }
        }
      }

      assert result == expected_result
    end
  end

  test "api call data module returns empty list", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-03 00:00:00Z]

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _, _ ->
        {:ok, []}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          dt1,
          dt2,
          "1d"
        )

      expected_result = %{
        "data" => %{
          "currentUser" => %{
            "apiCallsHistory" => []
          }
        }
      }

      assert result == expected_result
    end
  end

  test "api call data module returns error", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-03 00:00:00Z]

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _, _ ->
        {:error, "Something went wrong"}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          dt1,
          dt2,
          "1d"
        )

      %{"errors" => errors} = result

      assert length(errors) == 1
      error = errors |> List.first()
      assert error["message"] == "Something went wrong"
    end
  end

  describe "apiCallLimits" do
    test "returns the usage and the limits of the plan" do
      user = insert(:user, email: "api_call_limits@gmail.com")
      conn = setup_jwt_auth(build_conn(), user)

      {:ok, _} = Sanbase.ApiCallLimit.get_quota_db(:user, user)
      {:ok, :updated} = Sanbase.ApiCallLimit.update_usage_db(:user, user, 20, 0)

      assert fetch_api_call_limits(conn) == %{
               "plan" => "sanapi_free",
               "hasLimits" => true,
               "apiCallsMade" => %{"month" => 20},
               "apiCallsLimits" => %{"month" => 1000},
               "apiCallsRemaining" => %{"month" => 980}
             }
    end

    test "returns null limits for a user without api call limits" do
      user = insert(:user, email: "dev@santiment.net")
      conn = setup_jwt_auth(build_conn(), user)

      assert fetch_api_call_limits(conn) == %{
               "plan" => "sanapi_free",
               "hasLimits" => false,
               "apiCallsMade" => %{"month" => 0},
               "apiCallsLimits" => nil,
               "apiCallsRemaining" => nil
             }
    end
  end

  defp fetch_api_call_limits(conn) do
    query = """
    {
      currentUser{
        apiCallLimits{
          plan
          hasLimits
          apiCallsMade{ month }
          apiCallsLimits{ month }
          apiCallsRemaining{ month }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
    |> get_in(["data", "currentUser", "apiCallLimits"])
  end

  defp fetch_user_api_calls_count(conn, from, to, interval) do
    query = """
    {
      currentUser{
        apiCallsHistory(from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime
          apiCallsCount
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
  end
end
