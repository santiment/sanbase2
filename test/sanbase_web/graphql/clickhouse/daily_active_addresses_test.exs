defmodule SanbaseWeb.Graphql.Clickhouse.DailyActiveAddressesTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.DailyActiveAddresses

  setup do
    token = insert(:project, %{main_contract_address: "0x123"})

    ethereum =
      insert(:project, %{
        coinmarketcap_id: "ethereum",
        ticker: "ETH",
        main_contract_address: "0x456"
      })

    [
      token_contract: token.main_contract_address,
      token_slug: token.coinmarketcap_id,
      ethereum_contract: ethereum.main_contract_address,
      ethereum_slug: ethereum.coinmarketcap_id,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from daily active addresses calculation", context do
    with_mock DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok,
         [
           %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      response = execute_query(context.token_slug, context)
      addresses = parse_response(response)

      assert_called(
        DailyActiveAddresses.average_active_addresses(
          context.token_contract,
          context.from,
          context.to,
          context.interval
        )
      )

      assert addresses == [
               %{"activeAddresses" => 100, "datetime" => "2019-01-01T00:00:00Z"},
               %{"activeAddresses" => 200, "datetime" => "2019-01-02T00:00:00Z"}
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock DailyActiveAddresses, average_active_addresses: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context.token_slug, context)
      addresses = parse_response(response)

      assert_called(
        DailyActiveAddresses.average_active_addresses(
          context.token_contract,
          context.from,
          context.to,
          context.interval
        )
      )

      assert addresses == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context.token_slug, context)
               addresses = parse_response(response)
               assert addresses == nil
             end) =~
               ~s/[warn] Can't calculate daily active addresses for project with coinmarketcap_id: santiment. Reason: "Some error description here"/
    end
  end

  test "uses 1d as default interval", context do
    with_mock DailyActiveAddresses, average_active_addresses: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          dailyActiveAddresses(
            slug: "#{context.token_slug}",
            from: "#{context.from}",
            to: "#{context.to}")
          {
            datetime,
            activeAddresses
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

      assert_called(
        DailyActiveAddresses.average_active_addresses(
          context.token_contract,
          context.from,
          context.to,
          "1d"
        )
      )
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["dailyActiveAddresses"]
  end

  defp execute_query(slug, context) do
    query = active_addresses_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))
  end

  defp active_addresses_query(slug, from, to, interval) do
    """
    {
      dailyActiveAddresses(
        slug: "#{slug}",
        from: "#{from}",
        to: "#{to}",
        interval: "#{interval}"
      )
      {
        datetime,
        activeAddresses
      }
    }
    """
  end
end
