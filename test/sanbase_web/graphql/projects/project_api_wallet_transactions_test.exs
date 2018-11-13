defmodule SanbaseWeb.Graphql.ProjectApiWalletTransactionsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress,
    ExchangeAddress
  }

  alias Sanbase.Repo

  import Mock
  import SanbaseWeb.Graphql.TestHelpers

  @datetime1 DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
  @datetime2 DateTime.from_naive!(~N[2017-05-14 16:00:00], "Etc/UTC")
  @datetime3 DateTime.from_naive!(~N[2017-05-15 17:00:00], "Etc/UTC")
  @datetime4 DateTime.from_naive!(~N[2017-05-16 18:00:00], "Etc/UTC")
  @datetime5 DateTime.from_naive!(~N[2017-05-17 19:00:00], "Etc/UTC")
  @datetime6 DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")
  @exchange_wallet "0xe1e1e1e1e1e1e1"

  setup do
    slug = "santiment" <> Sanbase.TestUtils.random_string()

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", coinmarketcap_id: slug})
      |> Repo.insert!()

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: "0x" <> Sanbase.TestUtils.random_string()
    })
    |> Repo.insert!()

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: "0x" <> Sanbase.TestUtils.random_string()
    })
    |> Repo.insert!()

    %ExchangeAddress{}
    |> ExchangeAddress.changeset(%{
      address: @exchange_wallet,
      name: "Test exchange wallet"
    })
    |> Repo.insert!()

    # MarkExchanges GenServer is started by the top-level supervisor and not this process.
    # Due to the SQL Sandbox the added exchange address is not seen from the genserver.
    # Adding it manually
    Sanbase.Clickhouse.MarkExchanges.add_exchange_wallets([@exchange_wallet])

    [
      slug: slug,
      datetime_from: @datetime1,
      datetime_to: @datetime6
    ]
  end

  test "project in transactions for the whole interval", context do
    with_mock Sanbase.Clickhouse.EthTransfers,
      top_wallet_transfers: fn _, _, _, _, _ ->
        {:ok, eth_transfers_in()}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.slug}") {
          ethTopTransactions(
            from: "#{context.datetime_from}",
            to: "#{context.datetime_to}",
            transaction_type: IN){
              datetime,
              trxValue,
              fromAddress{ address, isExchange },
              toAddress{ address, isExchange }
          }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      trx_in = json_response(result, 200)["data"]["projectBySlug"]["ethTopTransactions"]

      assert %{
               "datetime" => "2017-05-16T18:00:00Z",
               "fromAddress" => %{"address" => "0x2", "isExchange" => false},
               "toAddress" => %{"address" => "0x1", "isExchange" => false},
               "trxValue" => 20_000.0
             } in trx_in

      assert %{
               "datetime" => "2017-05-17T19:00:00Z",
               "fromAddress" => %{"address" => "0x2", "isExchange" => false},
               "toAddress" => %{"address" => "0x1", "isExchange" => false},
               "trxValue" => 45_000.0
             } in trx_in

      assert %{
               "datetime" => "2017-05-13T15:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 500.0
             } not in trx_in

      assert %{
               "datetime" => "2017-05-14T16:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 1500.0
             } not in trx_in
    end
  end

  test "project out transactions for the whole interval", context do
    with_mock Sanbase.Clickhouse.EthTransfers,
      top_wallet_transfers: fn _, _, _, _, _ ->
        {:ok, eth_transfers_out()}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.slug}") {
          ethTopTransactions(
            from: "#{context.datetime_from}",
            to: "#{context.datetime_to}",
            transaction_type: OUT){
              datetime,
              trxValue,
              fromAddress{ address, isExchange },
              toAddress{ address, isExchange }
          }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      trx_out = json_response(result, 200)["data"]["projectBySlug"]["ethTopTransactions"]

      assert %{
               "datetime" => "2017-05-13T15:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 500.0
             } in trx_out

      assert %{
               "datetime" => "2017-05-14T16:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 1500.0
             } in trx_out

      assert %{
               "datetime" => "2017-05-15T17:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 2500.0
             } in trx_out

      assert %{
               "datetime" => "2017-05-17T19:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => @exchange_wallet, "isExchange" => true},
               "trxValue" => 5500.0
             } in trx_out

      assert %{
               "datetime" => "2017-05-18T20:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => @exchange_wallet, "isExchange" => true},
               "trxValue" => 6500.0
             } in trx_out
    end
  end

  test "project all wallet transactions in interval", context do
    with_mock Sanbase.Clickhouse.EthTransfers,
      top_wallet_transfers: fn _, _, _, _, _ ->
        {:ok, eth_transfers_in() ++ eth_transfers_out()}
      end do
      query = """
      {
        projectBySlug(slug: "#{context.slug}") {
          ethTopTransactions(
            from: "#{context.datetime_from}",
            to: "#{context.datetime_to}",
            transaction_type: ALL){
              datetime,
              trxValue,
              fromAddress{ address, isExchange },
              toAddress{ address, isExchange }
          }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "projectBySlug"))

      trx_all = json_response(result, 200)["data"]["projectBySlug"]["ethTopTransactions"]

      assert %{
               "datetime" => "2017-05-13T15:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-14T16:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 1500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-15T17:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 2500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-16T18:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => "0x2", "isExchange" => false},
               "trxValue" => 3500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-17T19:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => @exchange_wallet, "isExchange" => true},
               "trxValue" => 5500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-18T20:00:00Z",
               "fromAddress" => %{"address" => "0x1", "isExchange" => false},
               "toAddress" => %{"address" => @exchange_wallet, "isExchange" => true},
               "trxValue" => 6500.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-16T18:00:00Z",
               "fromAddress" => %{"address" => "0x2", "isExchange" => false},
               "toAddress" => %{"address" => "0x1", "isExchange" => false},
               "trxValue" => 20_000.0
             } in trx_all

      assert %{
               "datetime" => "2017-05-17T19:00:00Z",
               "fromAddress" => %{"address" => "0x2", "isExchange" => false},
               "toAddress" => %{"address" => "0x1", "isExchange" => false},
               "trxValue" => 45_000.0
             } in trx_all
    end
  end

  # Private functions

  defp eth_transfers_in() do
    [
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_527_472,
        datetime: @datetime4,
        from_address: "0x2",
        trx_position: 62,
        to_address: "0x1",
        trx_hash: "0xd4341953103d0d850d3284910213482dae5f7677c929f768d72f121e5a556fb3",
        trx_value: 20_000.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_569_715,
        datetime: @datetime5,
        from_address: "0x2",
        trx_position: 7,
        to_address: "0x1",
        trx_hash: "0x31a5d24e2fa078b88b49bd1180f6b29dfe145bb51b6f98543fe9bccf6e15bba2",
        trx_value: 45_000.0
      }
    ]
  end

  defp eth_transfers_out() do
    [
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_619_729,
        datetime: @datetime1,
        from_address: "0x1",
        trx_position: 0,
        to_address: "0x2",
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
        trx_value: 500.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_769_021,
        datetime: @datetime2,
        from_address: "0x1",
        trx_position: 2,
        to_address: "0x2",
        trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
        trx_value: 1500.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_770_231,
        datetime: @datetime3,
        from_address: "0x1",
        trx_position: 7,
        to_address: "0x2",
        trx_hash: "0x923f8054bf571ecd56db56f8aaf7b71b97f03ac7cf63e5cac929869cdbdd3863",
        trx_value: 2500.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_527_438,
        datetime: @datetime4,
        from_address: "0x1",
        trx_position: 56,
        to_address: "0x2",
        trx_hash: "0xa891e1bbe292e546f40d23772b53a396ae2d37697665157bc6e019c647e9531a",
        trx_value: 3500.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_569_693,
        datetime: @datetime5,
        from_address: "0x1",
        trx_position: 4,
        to_address: @exchange_wallet,
        trx_hash: "0x398772430a2e39f5f1addfbba56b7db1e30e5417de52c15001e157e350c18e52",
        trx_value: 5500.0
      },
      %Sanbase.Clickhouse.EthTransfers{
        block_number: 5_527_047,
        datetime: @datetime6,
        from_address: "0x1",
        trx_position: 58,
        to_address: @exchange_wallet,
        trx_hash: "0xa99da23a274c33d40d950fbc03bee7330e518ef6a9622ddd818cb9b967f9f520",
        trx_value: 6500.0
      }
    ]
  end
end
