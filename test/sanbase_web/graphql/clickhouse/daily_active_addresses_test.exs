defmodule SanbaseWeb.Graphql.Clickhouse.DailyActiveAddressesTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.DailyActiveAddresses

  setup do
    project1 =
      insert(:project, %{
        ticker: "PRJ1",
        coinmarketcap_id: "project1",
        main_contract_address: "0x123"
      })

    project2 =
      insert(:project, %{
        ticker: "PRJ2",
        coinmarketcap_id: "project2",
        main_contract_address: "0x456"
      })

    project_ethereum =
      insert(:project, %{
        coinmarketcap_id: "ethereum",
        ticker: "ETH",
        main_contract_address: "0x789"
      })

    [
      project: project1,
      contract: project1.main_contract_address,
      slug: project1.coinmarketcap_id,
      project2: project2,
      contract2: project2.main_contract_address,
      project_ethereum: project_ethereum,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "logs warning when calculation errors", context do
    with_mock DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_active_addresses_query(context, context.slug)
               addresses = parse_response(response)
               assert addresses == nil
             end) =~
               ~s/[warn] Can't calculate daily active addresses for project with coinmarketcap_id: project1. Reason: "Some error description here"/
    end
  end

  test "uses 1d as default interval", context do
    with_mock DailyActiveAddresses, average_active_addresses: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          dailyActiveAddresses(
            slug: "#{context.slug}",
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
          context.contract,
          context.from,
          context.to,
          "1d"
        )
      )
    end
  end

  describe "for tokens" do
    test "returns daily active addresses", context do
      with_mock DailyActiveAddresses,
        average_active_addresses: fn _, _, _, _ ->
          {:ok,
           [
             %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
             %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
           ]}
        end do
        response = execute_active_addresses_query(context, context.slug)
        addresses = parse_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.contract,
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

    test "returns daily active addresses with deposits", context do
      with_mock DailyActiveAddresses,
        average_active_addresses_with_deposits: fn _, _, _, _ ->
          {:ok,
           [
             %{
               active_addresses: 100,
               active_deposits: 10,
               share_of_deposits: 10.0,
               datetime: from_iso8601!("2019-01-01T00:00:00Z")
             },
             %{
               active_addresses: 200,
               active_deposits: 10,
               share_of_deposits: 5.0,
               datetime: from_iso8601!("2019-01-02T00:00:00Z")
             }
           ]}
        end do
        response = execute_active_addresses_with_deposits_query(context, context.slug)
        addresses = parse_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses_with_deposits(
            context.contract,
            context.from,
            context.to,
            context.interval
          )
        )

        assert addresses == [
                 %{
                   "activeAddresses" => 100,
                   "activeDeposits" => 10,
                   "shareOfDeposits" => 10.0,
                   "datetime" => "2019-01-01T00:00:00Z"
                 },
                 %{
                   "activeAddresses" => 200,
                   "activeDeposits" => 10,
                   "shareOfDeposits" => 5.0,
                   "datetime" => "2019-01-02T00:00:00Z"
                 }
               ]
      end
    end
  end

  describe "for ethereum" do
    test "returns daily active addresses", context do
      with_mock DailyActiveAddresses,
        average_active_addresses: fn _, _, _, _ ->
          {:ok,
           [
             %{active_addresses: 100, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
             %{active_addresses: 200, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
           ]}
        end do
        response =
          execute_active_addresses_query(context, context.project_ethereum.coinmarketcap_id)

        addresses = parse_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses(
            context.project_ethereum.ticker,
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

    test "returns daily active addresses with deposits", context do
      with_mock DailyActiveAddresses,
        average_active_addresses_with_deposits: fn _, _, _, _ ->
          {:ok,
           [
             %{
               active_addresses: 100,
               active_deposits: 10,
               share_of_deposits: 10.0,
               datetime: from_iso8601!("2019-01-01T00:00:00Z")
             },
             %{
               active_addresses: 200,
               active_deposits: 10,
               share_of_deposits: 5.0,
               datetime: from_iso8601!("2019-01-02T00:00:00Z")
             }
           ]}
        end do
        response =
          execute_active_addresses_with_deposits_query(
            context,
            context.project_ethereum.coinmarketcap_id
          )

        addresses = parse_response(response)

        assert_called(
          DailyActiveAddresses.average_active_addresses_with_deposits(
            context.project_ethereum.ticker,
            context.from,
            context.to,
            context.interval
          )
        )

        assert addresses == [
                 %{
                   "activeAddresses" => 100,
                   "activeDeposits" => 10,
                   "shareOfDeposits" => 10.0,
                   "datetime" => "2019-01-01T00:00:00Z"
                 },
                 %{
                   "activeAddresses" => 200,
                   "activeDeposits" => 10,
                   "shareOfDeposits" => 5.0,
                   "datetime" => "2019-01-02T00:00:00Z"
                 }
               ]
      end
    end
  end

  test "returns the average single value for active addresses", context do
    with_mock DailyActiveAddresses,
      average_active_addresses: fn _, _, _ ->
        {:ok, [{context.contract, 150}]}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.slug}") {
          averageDailyActiveAddresses(
            from: "#{context.from}",
            to: "#{context.to}")
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      active_addresses =
        json_response(result, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]

      assert active_addresses == 150
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["dailyActiveAddresses"]
  end

  defp execute_active_addresses_query(context, slug) do
    query = active_addresses_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))
  end

  defp execute_active_addresses_with_deposits_query(context, slug) do
    query = active_addresses_with_deposits_query(slug, context.from, context.to, context.interval)

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

  defp active_addresses_with_deposits_query(slug, from, to, interval) do
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
        activeDeposits
        shareOfDeposits
      }
    }
    """
  end
end
