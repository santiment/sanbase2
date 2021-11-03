defmodule SanbaseWeb.Graphql.BlockchainAddressTransactionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  require Sanbase.Utils.Config

  setup do
    project = insert(:random_project)
    {:ok, project: project}
  end

  test "Ethereum recent transactions", context do
    mock_fun =
      [
        fn -> {:ok, %{rows: eth_recent_transactions_result()}} end,
        fn -> {:ok, %{rows: labels_rows()}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 2)

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = recent_transactions_query("ETH")
      result = execute_query(context.conn, query, "recentTransactions")
      assert result == expected_eth_transactions()
    end)
  end

  test "Token recent transactions", context do
    mock_fun =
      [
        fn -> {:ok, %{rows: token_recent_transactions_result(context.project)}} end,
        fn -> {:ok, %{rows: labels_rows()}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 2)

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = recent_transactions_query("ERC20")
      result = execute_query(context.conn, query, "recentTransactions")
      assert result == expected_token_transactions(context.project)
    end)
  end

  # ClickhouseRepo will log the error
  @tag capture_log: true
  test "error when fetching recent transactions", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/2,
      {:error, "Internal error message"}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = recent_transactions_query("ERC20")
      error = execute_query_with_error(context.conn, query, "recentTransactions")

      assert error =~
               "Can't fetch Recent transactions for Address 0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8"
    end)
  end

  defp recent_transactions_query(type) do
    """
    {
      recentTransactions(
        address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        type: #{type}
      ) {
        fromAddress {
          address
          labels {
            name
          }
        }
        toAddress {
          address
          labels {
            name
          }
        }
        trxValue
        trxHash
        project {
          id
          slug
        }
      }
    }
    """
  end

  defp labels_rows() do
    [
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "centralized_exchange",
        ~s|{"comment":"Poloniex GNT","is_dex":false,"owner":"Poloniex","source":""}|
      ],
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "whale",
        ~s|{"rank": 58, "value": 1.1438690681177702e+24}|
      ]
    ]
  end

  defp expected_token_transactions(project) do
    [
      %{
        "fromAddress" => %{
          "address" => "0xc12d1c73ee7dc3615ba4e37e4abfdbddfa38907e",
          "labels" => []
        },
        "project" => %{
          "slug" => project.slug,
          "id" => to_string(project.id)
        },
        "toAddress" => %{
          "address" => "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
          "labels" => [%{"name" => "centralized_exchange"}, %{"name" => "whale"}]
        },
        "trxHash" => "0x4bd5d44da7f69c5227530728249431072087b5f9780eec704869fc768922121e",
        "trxValue" => 888_888.0
      }
    ]
  end

  defp expected_eth_transactions do
    [
      %{
        "fromAddress" => %{
          "address" => "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
          "labels" => ''
        },
        "toAddress" => %{
          "address" => "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
          "labels" => [%{"name" => "centralized_exchange"}, %{"name" => "whale"}]
        },
        "trxHash" => "0x21a56440bedb1a5c2f4adca4a6f9fbccf13bd741d63c0e3b2214a6ee418a5974",
        "trxValue" => 5.5,
        "project" => nil
      }
    ]
  end

  defp token_recent_transactions_result(project) do
    [
      [
        1_579_862_776,
        "0xc12d1c73ee7dc3615ba4e37e4abfdbddfa38907e",
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "0x4bd5d44da7f69c5227530728249431072087b5f9780eec704869fc768922121e",
        8.88888e13,
        project.slug,
        8
      ]
    ]
  end

  defp eth_recent_transactions_result do
    [
      [
        1_603_725_064,
        "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "0x21a56440bedb1a5c2f4adca4a6f9fbccf13bd741d63c0e3b2214a6ee418a5974",
        5.5e18
      ]
    ]
  end
end
