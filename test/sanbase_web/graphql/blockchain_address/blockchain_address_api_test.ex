defmodule SanbaseWeb.Graphql.BlockchainAddressApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  require Sanbase.Utils.Config

  test "Ethereum recent transactions", context do
    mock_fun =
      [
        fn -> {:ok, %{rows: eth_recent_transactions_result()}} end,
        fn -> {:ok, %{rows: labels_rows()}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 2)

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = eth_recent_transactions_query()
      result = execute_query(context.conn, query, "ethRecentTransactions")
      assert result == expected_eth_transactions()
    end)
  end

  test "Token recent transactions", context do
    mock_fun =
      [
        fn -> {:ok, %{rows: token_recent_transactions_result()}} end,
        fn -> {:ok, %{rows: labels_rows()}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 2)

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = token_recent_transactions_query()
      result = execute_query(context.conn, query, "tokenRecentTransactions")
      assert result == expected_token_transactions()
    end)
  end

  defp token_recent_transactions_query do
    """
    {
      tokenRecentTransactions(
        address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8"
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
        slug
      }
    }
    """
  end

  defp eth_recent_transactions_query do
    """
    {
      ethRecentTransactions(
        address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8"
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

  defp transactions do
    {:ok,
     [
       %Sanbase.Clickhouse.Erc20Transfers{
         block_number: 5_619_729,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-10 10:33:47], "Etc/UTC"),
         from_address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
         log_index: 0,
         to_address: "0x742d35cc6634c0532925a3b844bc454e4438f44e",
         trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
         trx_value: 4.5,
         trx_position: 2,
         slug: "santiment"
       }
     ]}
  end

  defp expected_token_transactions do
    [
      %{
        "fromAddress" => %{
          "address" => "0xc12d1c73ee7dc3615ba4e37e4abfdbddfa38907e",
          "labels" => []
        },
        "slug" => "kickico",
        "toAddress" => %{
          "address" => "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
          "labels" => [%{"name" => "whale"}, %{"name" => "centralized_exchange"}]
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
          "labels" => [%{"name" => "whale"}, %{"name" => "centralized_exchange"}]
        },
        "trxHash" => "0x21a56440bedb1a5c2f4adca4a6f9fbccf13bd741d63c0e3b2214a6ee418a5974",
        "trxValue" => 5.5
      }
    ]
  end

  defp token_recent_transactions_result do
    [
      [
        1_579_862_776,
        "0xc12d1c73ee7dc3615ba4e37e4abfdbddfa38907e",
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "0x4bd5d44da7f69c5227530728249431072087b5f9780eec704869fc768922121e",
        8.88888e13,
        "kickico",
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
