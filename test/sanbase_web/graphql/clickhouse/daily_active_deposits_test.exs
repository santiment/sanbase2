defmodule SanbaseWeb.Graphql.Clickhouse.DailyActiveDepositsTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.DailyActiveDeposits

  setup do
    project =
      insert(:project, %{
        coinmarketcap_id: "santiment",
        ticker: "SAN",
        main_contract_address: "0x123"
      })

    [
      contract: project.main_contract_address,
      slug: project.coinmarketcap_id,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from daily active deposits calculation", context do
    with_mock DailyActiveDeposits,
      active_deposits: fn _, _, _, _ ->
        {:ok,
         [
           %{active_deposits: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{active_deposits: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      response = execute_query(context)
      deposits = parse_response(response)

      assert_called(
        DailyActiveDeposits.active_deposits(
          context.contract,
          context.from,
          context.to,
          context.interval
        )
      )

      assert deposits == [
               %{"activeDeposits" => 100, "datetime" => "2019-01-01T00:00:00Z"},
               %{"activeDeposits" => 200, "datetime" => "2019-01-02T00:00:00Z"}
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock DailyActiveDeposits, active_deposits: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      deposits = parse_response(response)

      assert_called(
        DailyActiveDeposits.active_deposits(
          context.contract,
          context.from,
          context.to,
          context.interval
        )
      )

      assert deposits == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock DailyActiveDeposits,
      active_deposits: fn _, _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               deposits = parse_response(response)
               assert deposits == nil
             end) =~
               ~s/[warn] Can't calculate daily active deposits for project with coinmarketcap_id: santiment. Reason: "Some error description here"/
    end
  end

  test "uses 1d as default interval", context do
    with_mock DailyActiveDeposits, active_deposits: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          dailyActiveDeposits(
            slug: "#{context.slug}",
            from: "#{context.from}",
            to: "#{context.to}")
          {
            datetime,
            activeDeposits
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveDeposits"))

      assert_called(
        DailyActiveDeposits.active_deposits(context.contract, context.from, context.to, "1d")
      )
    end
  end

  test "works with empty interval", context do
    with_mocks([
      {DailyActiveDeposits, [:passthrough], active_deposits: fn _, _, _, _ -> {:ok, []} end},
      {DailyActiveDeposits, [:passthrough],
       first_datetime: fn _ -> {:ok, from_iso8601!("2019-01-01T00:00:00Z")} end}
    ]) do
      query = active_deposits_query(context.slug, context.from, context.to, "")

      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveDeposits"))

      assert_called(
        DailyActiveDeposits.active_deposits(context.contract, context.from, context.to, "3600s")
      )
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["dailyActiveDeposits"]
  end

  defp execute_query(context) do
    query = active_deposits_query(context.slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "dailyActiveDeposits"))
  end

  defp active_deposits_query(slug, from, to, interval) do
    """
    {
      dailyActiveDeposits(
        slug: "#{slug}",
        from: "#{from}",
        to: "#{to}",
        interval: "#{interval}"
      )
      {
        datetime,
        activeDeposits
      }
    }
    """
  end
end
