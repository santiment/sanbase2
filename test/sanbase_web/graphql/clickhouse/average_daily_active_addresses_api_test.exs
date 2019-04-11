defmodule SanbaseWeb.Graphql.Clickhouse.AverageDailyActiveAddressesApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    project = insert(:project, %{main_contract_address: "0x123123"})
    insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH", name: "Ethereum"})
    insert(:project, %{coinmarketcap_id: "bitcoin", ticker: "BTC", name: "Bitcoin"})
    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-23 00:00:00], "Etc/UTC")

    [
      project: project,
      datetime1: datetime1,
      datetime2: datetime2
    ]
  end

  test "average daily active addreses for projectBySlug", context do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _ ->
        {:ok, [{"#{context.project.main_contract_address}", 10707}]}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.project.coinmarketcap_id}") {
          averageDailyActiveAddresses(
            from: "#{context.datetime1}",
            to: "#{context.datetime2}")
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      active_addresses =
        json_response(result, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]

      assert active_addresses == 10707
    end
  end

  test "average daily active addreses is 0 if the database returns empty list", context do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _ ->
        {:ok, []}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.project.coinmarketcap_id}") {
          averageDailyActiveAddresses(
            from: "#{context.datetime1}",
            to: "#{context.datetime2}")
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      active_addresses =
        json_response(result, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]

      assert active_addresses == 0
    end
  end

  test "average daily active addresses works for ethereum and bitcoin", context do
    with_mocks([
      {Sanbase.Clickhouse.Erc20DailyActiveAddresses, [:passthrough],
       average_active_addresses: fn _, _, _ ->
         {:ok, [{"#{context.project.main_contract_address}", 10707}]}
       end},
      {Sanbase.Clickhouse.EthDailyActiveAddresses, [:passthrough],
       average_active_addresses: fn _, _ ->
         {:ok, 250_000}
       end},
      {Sanbase.Clickhouse.Bitcoin, [:passthrough],
       average_active_addresses: fn _, _ ->
         {:ok, 750_000}
       end}
    ]) do
      query = """
      {
        allProjects {
          averageDailyActiveAddresses(
            from: "#{context.datetime1}",
            to: "#{context.datetime2}")
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))

      active_addresses = json_response(result, 200)["data"]["allProjects"]

      assert active_addresses == [
               %{"averageDailyActiveAddresses" => 750_000},
               %{"averageDailyActiveAddresses" => 250_000},
               %{"averageDailyActiveAddresses" => 10707}
             ]
    end
  end
end
