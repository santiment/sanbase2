defmodule SanbaseWeb.Graphql.Clickhouse.AverageDailyActiveAddressesApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    project = insert(:project, %{main_contract_address: "0x123123"})
    insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH", name: "Ethereum"})
    insert(:project, %{coinmarketcap_id: "bitcoin", ticker: "BTC", name: "Bitcoin"})
    from = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2017-05-23 00:00:00], "Etc/UTC")

    [
      project: project,
      from: from,
      to: to
    ]
  end

  test "average daily active addreses for erc20 project", context do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _ ->
        {:ok, [{"#{context.project.main_contract_address}", 10707}]}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.project.coinmarketcap_id}") {
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

      assert active_addresses == 10707
    end
  end

  test "average daily active addreses for Bitcoin", context do
    with_mock Sanbase.Clickhouse.Bitcoin,
      average_active_addresses: fn _, _ ->
        {:ok, 543_223}
      end do
      query = """
      {
        projectBySlug(slug: "bitcoin") {
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

      assert active_addresses == 543_223
    end
  end

  test "average daily active addreses for Ethereum", context do
    with_mock Sanbase.Clickhouse.EthDailyActiveAddresses,
      average_active_addresses: fn _, _ ->
        {:ok, 221_007}
      end do
      query = """
      {
        projectBySlug(slug: "ethereum") {
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

      assert active_addresses == 221_007
    end
  end

  test "average daily active addreses are 0 in case of database error", context do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _ ->
        {:error, "Some error"}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.project.coinmarketcap_id}") {
          averageDailyActiveAddresses(
            from: "#{context.from}",
            to: "#{context.to}")
        }
      }
      """

      assert capture_log(fn ->
               result =
                 context.conn
                 |> post("/graphql", query_skeleton(query, "projectBySlug"))

               active_addresses =
                 json_response(result, 200)["data"]["projectBySlug"][
                   "averageDailyActiveAddresses"
                 ]

               assert active_addresses == 0
             end) =~ "[warn] Cannot fetch average active addresses for ERC20 contracts"
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

      assert active_addresses == 0
    end
  end

  test "average DAA for ERC20 tokens, ethereum and bitcoin requested together", context do
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
            from: "#{context.from}",
            to: "#{context.to}")
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
