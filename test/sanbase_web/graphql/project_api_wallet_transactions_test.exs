defmodule SanbaseWeb.Graphql.ProjectApiWalletTransactionsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "TESTXYZ"
    Store.drop_measurement(ticker)

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: ticker})
      |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 16:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 17:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 18:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 19:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")

    [
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 1500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123b"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 2500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123c"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 3500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123d"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 100_000, from_addr: "0x2", to_addr: "0x1", trx_hash: "0x123e"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123f"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 45000, from_addr: "0x2", to_addr: "0x1", trx_hash: "0x123g"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 6500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x123h"},
        tags: [transaction_type: "out"],
        name: ticker
      }
    ]
    |> Store.import()

    [
      project: p,
      ticker: ticker,
      datetime_from: datetime1,
      datetime_to: datetime6
    ]
  end

  test "project in transactions for the whole interval", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethTopTransactions(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}",
          transaction_type: IN){
            datetime,
            trxValue,
            fromAddress,
            toAddress
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    trx_in = json_response(result, 200)["data"]["project"]["ethTopTransactions"]

    assert %{
             "datetime" => "2017-05-16T18:00:00Z",
             "fromAddress" => "0x2",
             "toAddress" => "0x1",
             "trxValue" => "100000"
           } in trx_in

    assert %{
             "datetime" => "2017-05-17T19:00:00Z",
             "fromAddress" => "0x2",
             "toAddress" => "0x1",
             "trxValue" => "45000"
           } in trx_in
  end

  test "project out transactions for the whole interval", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethTopTransactions(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}",
          transaction_type: OUT){
            datetime,
            trxValue,
            fromAddress,
            toAddress
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    trx_out = json_response(result, 200)["data"]["project"]["ethTopTransactions"]

    assert %{
             "datetime" => "2017-05-13T15:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "500"
           } in trx_out

    assert %{
             "datetime" => "2017-05-14T16:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "1500"
           } in trx_out

    assert %{
             "datetime" => "2017-05-15T17:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "2500"
           } in trx_out

    assert %{
             "datetime" => "2017-05-16T18:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "3500"
           } in trx_out

    assert %{
             "datetime" => "2017-05-17T19:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "5500"
           } in trx_out

    assert %{
             "datetime" => "2017-05-18T20:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "6500"
           } in trx_out
  end

  test "project all wallet transactions in interval", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethTopTransactions(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}",
          transaction_type: ALL){
            datetime,
            trxValue,
            fromAddress,
            toAddress
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    trx_all = json_response(result, 200)["data"]["project"]["ethTopTransactions"]

    assert %{
             "datetime" => "2017-05-13T15:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-14T16:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "1500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-15T17:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "2500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-16T18:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "3500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-17T19:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "5500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-18T20:00:00Z",
             "fromAddress" => "0x1",
             "toAddress" => "0x2",
             "trxValue" => "6500"
           } in trx_all

    assert %{
             "datetime" => "2017-05-16T18:00:00Z",
             "fromAddress" => "0x2",
             "toAddress" => "0x1",
             "trxValue" => "100000"
           } in trx_all

    assert %{
             "datetime" => "2017-05-17T19:00:00Z",
             "fromAddress" => "0x2",
             "toAddress" => "0x1",
             "trxValue" => "45000"
           } in trx_all
  end
end
