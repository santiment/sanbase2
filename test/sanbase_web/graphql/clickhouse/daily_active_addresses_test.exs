defmodule SanbaseWeb.Graphql.Clickhouse.DailyActiveAddressesTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.{
    Bitcoin,
    DailyActiveAddresses,
    EthDailyActiveAddresses,
    Erc20DailyActiveAddresses
  }

  setup do
    token = insert(:project, %{main_contract_address: "0x123"})
    ethereum = insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH"})
    bitcoin = insert(:project, %{coinmarketcap_id: "bitcoin", ticker: "BTC", name: "Bitcoin"})

    [
      token_contract: token.main_contract_address,
      token_slug: token.coinmarketcap_id,
      ethereum_slug: ethereum.coinmarketcap_id,
      ethereum_ticker: ethereum.ticker,
      bitcoin_slug: bitcoin.coinmarketcap_id,
      bitcoin_ticker: bitcoin.ticker,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  describe "for dailyActiveAddresses query" do
    test "returns active addresses for erc20 tokens", context do
      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ ->
                  {:ok,
                   [
                     %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                     %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
                   ]}
                end do
        response = execute_daa_query(context.token_slug, context)
        addresses = parse_daa_response(response)

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

    test "returns active addresses for ethereum", context do
      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ ->
                  {:ok,
                   [
                     %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                     %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
                   ]}
                end do
        response = execute_daa_query(context.ethereum_slug, context)
        addresses = parse_daa_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.ethereum_ticker,
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

    test "returns active addresses for bitcoin", context do
      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ ->
                  {:ok,
                   [
                     %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                     %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
                   ]}
                end do
        response = execute_daa_query(context.bitcoin_slug, context)
        addresses = parse_daa_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.bitcoin_ticker,
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
      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ -> {:ok, []} end do
        response = execute_daa_query(context.token_slug, context)
        addresses = parse_daa_response(response)

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
      error = "Some error description here"

      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ ->
                  {:error, error}
                end do
        assert capture_log(fn ->
                 response = execute_daa_query(context.token_slug, context)
                 addresses = parse_daa_response(response)
                 assert addresses == nil
               end) =~
                 graphql_error_msg("Daily Active Addresses", context.token_slug, error)
      end
    end

    test "works with empty interval for erc20 tokens", context do
      with_mocks([
        {DailyActiveAddresses, [:passthrough],
         average_active_addresses: fn _, _, _, _ -> {:ok, []} end},
        {Erc20DailyActiveAddresses, [:passthrough],
         first_datetime: fn _ -> {:ok, from_iso8601!("2019-01-01T00:00:00Z")} end}
      ]) do
        query = active_addresses_query(context.token_slug, context.from, context.to, "")

        context.conn
        |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.token_contract,
            context.from,
            context.to,
            "86400s"
          )
        )
      end
    end

    test "works with empty interval for ethereum", context do
      with_mocks([
        {DailyActiveAddresses, [:passthrough],
         average_active_addresses: fn _, _, _, _ -> {:ok, []} end},
        {EthDailyActiveAddresses, [:passthrough],
         first_datetime: fn _ -> {:ok, from_iso8601!("2019-01-01T00:00:00Z")} end}
      ]) do
        query = active_addresses_query(context.ethereum_slug, context.from, context.to, "")

        context.conn
        |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.ethereum_ticker,
            context.from,
            context.to,
            "86400s"
          )
        )
      end
    end

    test "works with empty interval for bitcoin", context do
      with_mocks([
        {DailyActiveAddresses, [:passthrough],
         average_active_addresses: fn _, _, _, _ -> {:ok, []} end},
        {Bitcoin, [:passthrough],
         first_datetime: fn _ -> {:ok, from_iso8601!("2019-01-01T00:00:00Z")} end}
      ]) do
        query = active_addresses_query(context.bitcoin_slug, context.from, context.to, "")

        context.conn
        |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.bitcoin_ticker,
            context.from,
            context.to,
            "86400s"
          )
        )
      end
    end

    test "uses 1d as default interval", context do
      with_mock DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _, _ -> {:ok, []} end do
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
  end

  describe "for projectBySlug query" do
    test "average daily active addresses for erc20 project", context do
      with_mock Erc20DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _ ->
                  {:ok, [{"#{context.token_contract}", 10_707}]}
                end do
        response = execute_project_by_slug_query(context.token_slug, context)
        addresses = parse_project_by_slug_response(response)

        assert addresses == 10_707
      end
    end

    test "average daily active addresses for Bitcoin", context do
      with_mock Bitcoin, [:passthrough],
        average_active_addresses: fn _, _ ->
          {:ok, 543_223}
        end do
        response = execute_project_by_slug_query(context.bitcoin_slug, context)
        addresses = parse_project_by_slug_response(response)

        assert addresses == 543_223
      end
    end

    test "average daily active addresses for Ethereum", context do
      with_mock EthDailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _ ->
                  {:ok, 221_007}
                end do
        response = execute_project_by_slug_query(context.ethereum_slug, context)
        addresses = parse_project_by_slug_response(response)

        assert addresses == 221_007
      end
    end

    test "average daily active addresses are 0 in case of database error", context do
      with_mock Erc20DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _ ->
                  {:error, "Some error"}
                end do
        assert capture_log(fn ->
                 response = execute_project_by_slug_query(context.token_slug, context)
                 addresses = parse_project_by_slug_response(response)

                 assert addresses == 0
               end) =~ "[warn] Cannot fetch average active addresses for ERC20 contracts"
      end
    end

    test "average daily active addresses is 0 if the database returns empty list", context do
      with_mock Erc20DailyActiveAddresses,
                [:passthrough],
                average_active_addresses: fn _, _, _ ->
                  {:ok, []}
                end do
        response = execute_project_by_slug_query(context.token_slug, context)
        addresses = parse_project_by_slug_response(response)

        assert addresses == 0
      end
    end
  end

  describe "for allProjects query" do
    test "average DAA for ERC20 tokens, ethereum and bitcoin requested together", context do
      with_mocks([
        {Erc20DailyActiveAddresses, [:passthrough],
         average_active_addresses: fn _, _, _ ->
           {:ok, [{"#{context.token_contract}", 10_707}]}
         end},
        {EthDailyActiveAddresses, [:passthrough],
         average_active_addresses: fn _, _ ->
           {:ok, 250_000}
         end},
        {Bitcoin, [:passthrough],
         average_active_addresses: fn _, _ ->
           {:ok, 750_000}
         end}
      ]) do
        query = """
        {
          allProjects {
            averageDailyActiveAddresses(
              from: "#{context.from}",
              to: "#{context.to}")
          }
        }
        """

        result =
          context.conn
          |> post("/graphql", query_skeleton(query, "allProjects"))

        active_addresses = json_response(result, 200)["data"]["allProjects"]

        assert %{"averageDailyActiveAddresses" => 750_000} in active_addresses
        assert %{"averageDailyActiveAddresses" => 10_707} in active_addresses
        assert %{"averageDailyActiveAddresses" => 250_000} in active_addresses
      end
    end
  end

  defp parse_daa_response(response) do
    json_response(response, 200)["data"]["dailyActiveAddresses"]
  end

  defp parse_project_by_slug_response(response) do
    json_response(response, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]
  end

  defp execute_daa_query(slug, context) do
    query = active_addresses_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))
  end

  defp execute_project_by_slug_query(slug, context) do
    query = project_by_slug_query(slug, context.from, context.to)

    context.conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
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

  defp project_by_slug_query(slug, from, to) do
    """
    {
      projectBySlug(slug: "#{slug}") {
        averageDailyActiveAddresses(
          from: "#{from}",
          to: "#{to}")
      }
    }
    """
  end
end
