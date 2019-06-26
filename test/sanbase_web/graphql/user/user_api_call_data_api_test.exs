defmodule SanbaseWeb.Graphql.UserApiCallDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn}
  end

  test "api call data module returns data", context do
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-02T00:00:00Z"
    dt3_str = "2019-01-03T00:00:00Z"

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _ ->
        {:ok,
         [
           %{datetime: from_iso8601!(dt1_str), api_calls_count: 400},
           %{datetime: from_iso8601!(dt2_str), api_calls_count: 100},
           %{datetime: from_iso8601!(dt3_str), api_calls_count: 200}
         ]}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          from_iso8601!(dt1_str),
          from_iso8601!(dt3_str),
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
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-03T00:00:00Z"

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _ ->
        {:ok, []}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          from_iso8601!(dt1_str),
          from_iso8601!(dt2_str),
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
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-03T00:00:00Z"

    with_mock Sanbase.Clickhouse.ApiCallData,
      api_call_history: fn _, _, _, _ ->
        {:error, "Something went wrong"}
      end do
      result =
        fetch_user_api_calls_count(
          context.conn,
          from_iso8601!(dt1_str),
          from_iso8601!(dt2_str),
          "1d"
        )

      %{"errors" => errors} = result

      assert length(errors) == 1
      error = errors |> List.first()
      assert error["message"] == "Something went wrong"
    end
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
