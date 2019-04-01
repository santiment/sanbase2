defmodule SanbaseWeb.Graphql.Clickhouse.RealizedValueTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.RealizedValue

  setup do
    project = insert(:project, %{coinmarketcap_id: "santiment", ticker: "SAN"})

    [
      slug: project.coinmarketcap_id,
      from: allowed_free_user_from(),
      to: allowed_free_user_to(),
      interval: "1d"
    ]
  end

  test "returns data from Realized Value calculation", context do
    with_mock RealizedValue,
      realized_value: fn _, _, _, _ ->
        {:ok,
         [
           %{
             realized_value: 100_000,
             non_exchange_realized_value: 10_000,
             datetime: allowed_free_user_from()
           },
           %{
             realized_value: 200_000,
             non_exchange_realized_value: 20_000,
             datetime: Timex.shift(allowed_free_user_from(), days: 1)
           }
         ]}
      end do
      response = execute_query(context)
      values = parse_response(response)

      assert_called(
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)
      )

      assert values == [
               %{
                 "realizedValue" => 100_000,
                 "nonExchangeRealizedValue" => 10_000,
                 "datetime" => DateTime.to_iso8601(allowed_free_user_from())
               },
               %{
                 "realizedValue" => 200_000,
                 "nonExchangeRealizedValue" => 20_000,
                 "datetime" => DateTime.to_iso8601(Timex.shift(allowed_free_user_from(), days: 1))
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock RealizedValue, realized_value: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      values = parse_response(response)

      assert_called(
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)
      )

      assert values == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock RealizedValue,
      realized_value: fn _, _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               values = parse_response(response)
               assert values == nil
             end) =~
               ~s/[warn] Can't calculate Realized Value for project with coinmarketcap_id: santiment. Reason: "Some error description here"/
    end
  end

  test "uses 1d as default interval", context do
    with_mock RealizedValue, realized_value: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          realizedValue(slug: "#{context.slug}", from: "#{context.from}", to: "#{context.to}"){
            datetime
            realizedValue,
            nonExchangeRealizedValue
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "realizedValue"))

      assert_called(RealizedValue.realized_value(context.slug, context.from, context.to, "1d"))
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["realizedValue"]
  end

  defp execute_query(context) do
    query = realized_value_query(context.slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "realizedValue"))
  end

  defp realized_value_query(slug, from, to, interval) do
    """
      {
        realizedValue(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          realizedValue,
          nonExchangeRealizedValue
        }
      }
    """
  end
end
