defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalance.MinersBalanceTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance.MinersBalance

  setup do
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from calculation", context do
    with_mock MinersBalance,
      historical_balance: fn _, _, _, _ ->
        {:ok,
         [
           %{
             balance: 100,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             balance: 200,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(
        MinersBalance.historical_balance(context.slug, context.from, context.to, context.interval)
      )

      assert result == [
               %{
                 "balance" => 100,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "balance" => 200,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock MinersBalance, historical_balance: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(
        MinersBalance.historical_balance(context.slug, context.from, context.to, context.interval)
      )

      assert result == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock MinersBalance,
      historical_balance: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context.slug, context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Miners Balance", context.slug, error)
    end
  end

  test "uses 1d as default interval", context do
    with_mock MinersBalance, historical_balance: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          minersBalance(slug: "#{context.slug}", from: "#{context.from}", to: "#{context.to}"){
            datetime,
            balance
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "minersBalance"))

      assert_called(
        MinersBalance.historical_balance(context.slug, context.from, context.to, "1d")
      )
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["minersBalance"]
  end

  defp execute_query(slug, context) do
    query = miners_balance_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "balance"))
  end

  defp miners_balance_query(slug, from, to, interval) do
    """
      {
        minersBalance(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          balance
        }
      }
    """
  end
end
