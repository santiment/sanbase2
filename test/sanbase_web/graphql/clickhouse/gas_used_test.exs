defmodule SanbaseWeb.Graphql.Clickhouse.GasUsedTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog

  alias Sanbase.Clickhouse.GasUsed

  setup do
    [
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from calculation", context do
    with_mock GasUsed,
      gas_used: fn _, _, _ ->
        {:ok,
         [
           %{
             eth_gas_used: 100,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             eth_gas_used: 200,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context)
      result = parse_response(response)

      assert_called(GasUsed.gas_used(context.from, context.to, context.interval))

      assert result == [
               %{
                 "ethGasUsed" => 100,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "ethGasUsed" => 200,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock GasUsed, gas_used: fn _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      result = parse_response(response)

      assert_called(GasUsed.gas_used(context.from, context.to, context.interval))
      assert result == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock GasUsed,
      gas_used: fn _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               result = parse_response(response)
               assert result == nil
             end) =~ ~s/[warn] Can't calculate gas used. Reason: "Some error description here"/
    end
  end

  test "uses 1d as default interval", context do
    with_mock GasUsed, gas_used: fn _, _, _ -> {:ok, []} end do
      query = """
        {
          gasUsed(from: "#{context.from}", to: "#{context.to}"){
            datetime,
            ethGasUsed
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "gasUsed"))

      assert_called(GasUsed.gas_used(context.from, context.to, "1d"))
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["gasUsed"]
  end

  defp execute_query(context) do
    query = gas_used_query(context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "gasUsed"))
  end

  defp gas_used_query(from, to, interval) do
    """
      {
        gasUsed(from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          ethGasUsed
        }
      }
    """
  end
end
