defmodule SanbaseWeb.Graphql.ProjectApiWalletTransactionsTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock, only: [assert_called: 1]
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  @datetime1 ~U[2017-05-13 15:00:00Z]
  @datetime2 ~U[2017-05-14 16:00:00Z]
  @datetime3 ~U[2017-05-15 17:00:00Z]
  @datetime4 ~U[2017-05-16 18:00:00Z]
  @datetime5 ~U[2017-05-17 19:00:00Z]
  @datetime6 ~U[2017-05-18 20:00:00Z]

  @exchange_wallet "0xe1e1e1e1e1e1e1"

  setup_all_with_mocks([
    {Sanbase.ClickhouseRepo, [:passthrough], [query: fn _, _ -> {:ok, %{rows: []}} end]}
  ]) do
    []
  end

  setup do
    project = insert(:random_erc20_project)

    # MarkExchanges GenServer is started by the top-level supervisor and not this process.
    # Due to the SQL Sandbox the added exchange address is not seen from the genserver.
    # Adding it manually
    Sanbase.Clickhouse.MarkExchanges.add_exchange_wallets([@exchange_wallet])

    [
      slug: project.slug,
      datetime_from: @datetime1,
      datetime_to: @datetime6
    ]
  end

  test "top transfers for a slug", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Transfers.Erc20Transfers.top_transactions/7,
      {:ok, all_transfers()}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        topTransfers(
          slug: "#{context.slug}"
          from: "#{context.datetime_from}"
          to: "#{context.datetime_to}"){
            datetime
            trxValue
            fromAddress{ address isExchange labels { name metadata } }
            toAddress{ address isExchange labels { name metadata } }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "topTransfers"))

      transactions = json_response(result, 200)["data"]["topTransfers"]

      assert_called(Sanbase.Transfers.Erc20Transfers.top_transactions(:_, :_, :_, :_, :_, :_, :_))

      assert transactions == [
               %{
                 "datetime" => "2017-05-13T15:00:00Z",
                 "fromAddress" => %{"address" => "0x1", "isExchange" => false, "labels" => []},
                 "toAddress" => %{
                   "address" => "0xe1e1e1e1e1e1e1",
                   "isExchange" => true,
                   "labels" => []
                 },
                 "trxValue" => 500.0
               },
               %{
                 "datetime" => "2017-05-14T16:00:00Z",
                 "fromAddress" => %{"address" => "0x1", "isExchange" => false, "labels" => []},
                 "toAddress" => %{"address" => "0x2", "isExchange" => false, "labels" => []},
                 "trxValue" => 1.5e3
               },
               %{
                 "datetime" => "2017-05-16T18:00:00Z",
                 "fromAddress" => %{"address" => "0x2", "isExchange" => false, "labels" => []},
                 "toAddress" => %{"address" => "0x1", "isExchange" => false, "labels" => []},
                 "trxValue" => 2.0e4
               },
               %{
                 "datetime" => "2017-05-17T19:00:00Z",
                 "fromAddress" => %{
                   "address" => "0xe1e1e1e1e1e1e1",
                   "isExchange" => true,
                   "labels" => []
                 },
                 "toAddress" => %{"address" => "0x1", "isExchange" => false, "labels" => []},
                 "trxValue" => 4.5e4
               }
             ]
    end)
  end

  test "top transfers for an address and slug", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Transfers.Erc20Transfers.top_wallet_transactions/8,
      {:ok, address_transfers()}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        topTransfers(
          slug: "#{context.slug}"
          from: "#{context.datetime_from}"
          to: "#{context.datetime_to}"
          addressSelector: {address: "#{@exchange_wallet}" transaction_type: ALL}){
            datetime
            trxValue
            fromAddress{ address isExchange labels { name metadata } }
            toAddress{ address isExchange labels { name metadata } }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "topTransfers"))
        |> json_response(200)

      assert_called(
        Sanbase.Transfers.Erc20Transfers.top_wallet_transactions(:_, :_, :_, :_, :_, :_, :_, :_)
      )

      transactions = result["data"]["topTransfers"]

      assert transactions ==
               [
                 %{
                   "datetime" => "2017-05-13T15:00:00Z",
                   "fromAddress" => %{"address" => "0x1", "isExchange" => false, "labels" => []},
                   "toAddress" => %{
                     "address" => "0xe1e1e1e1e1e1e1",
                     "isExchange" => true,
                     "labels" => []
                   },
                   "trxValue" => 500.0
                 },
                 %{
                   "datetime" => "2017-05-15T17:00:00Z",
                   "fromAddress" => %{
                     "address" => "0xe1e1e1e1e1e1e1",
                     "isExchange" => true,
                     "labels" => []
                   },
                   "toAddress" => %{"address" => "0x2", "isExchange" => false, "labels" => []},
                   "trxValue" => 1.5e3
                 },
                 %{
                   "datetime" => "2017-05-18T20:00:00Z",
                   "fromAddress" => %{
                     "address" => "0xe1e1e1e1e1e1e1",
                     "isExchange" => true,
                     "labels" => []
                   },
                   "toAddress" => %{"address" => "0x2", "isExchange" => false, "labels" => []},
                   "trxValue" => 2.5e3
                 }
               ]
    end)
  end

  # Private functions

  defp all_transfers() do
    [
      %{
        datetime: @datetime1,
        from_address: "0x1",
        trx_position: 0,
        to_address: "0xe1e1e1e1e1e1e1",
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
        trx_value: 500.0
      },
      %{
        datetime: @datetime2,
        from_address: "0x1",
        trx_position: 2,
        to_address: "0x2",
        trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
        trx_value: 1500.0
      },
      %{
        datetime: @datetime4,
        from_address: "0x2",
        trx_position: 62,
        to_address: "0x1",
        trx_hash: "0xd4341953103d0d850d3284910213482dae5f7677c929f768d72f121e5a556fb3",
        trx_value: 20_000.0
      },
      %{
        datetime: @datetime5,
        from_address: "0xe1e1e1e1e1e1e1",
        trx_position: 7,
        to_address: "0x1",
        trx_hash: "0x31a5d24e2fa078b88b49bd1180f6b29dfe145bb51b6f98543fe9bccf6e15bba2",
        trx_value: 45_000.0
      }
    ]
  end

  defp address_transfers do
    [
      %{
        datetime: @datetime1,
        from_address: "0x1",
        trx_position: 0,
        to_address: "0xe1e1e1e1e1e1e1",
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
        trx_value: 500.0
      },
      %{
        datetime: @datetime3,
        from_address: "0xe1e1e1e1e1e1e1",
        trx_position: 2,
        to_address: "0x2",
        trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
        trx_value: 1500.0
      },
      %{
        datetime: @datetime6,
        from_address: "0xe1e1e1e1e1e1e1",
        trx_position: 7,
        to_address: "0x2",
        trx_hash: "0x923f8054bf571ecd56db56f8aaf7b71b97f03ac7cf63e5cac929869cdbdd3863",
        trx_value: 2500.0
      }
    ]
  end
end
