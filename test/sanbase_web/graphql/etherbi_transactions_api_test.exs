defmodule Sanbase.Github.EtherbiTransactionsApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.Transactions.Store

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    address = "0x12345678"
    Store.drop_measurement(ticker)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:47:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 21:49:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 21:51:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 21:53:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-13 21:57:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-13 21:59:00], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "5000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "3000", ticker: ticker},
        tags: [transaction_type: "out", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "6000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "4000", ticker: ticker},
        tags: [transaction_type: "out", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "9000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "15000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "18000", ticker: ticker},
        tags: [transaction_type: "out", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "1000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "10000", ticker: ticker},
        tags: [transaction_type: "out", address: address],
        name: ticker
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "50000", ticker: ticker},
        tags: [transaction_type: "in", address: address],
        name: ticker
      }
    ])

    [
      address: address,
      ticker: ticker,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      datetime5: datetime5,
      datetime6: datetime6,
      datetime7: datetime7,
      datetime8: datetime8
    ]
  end

  test "fetch in transactions", context do
    query = """
    {
      exchangeFundFlow(
        ticker: "#{context.ticker}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        transaction_type: IN) {
          datetime
          transactionVolume
          address
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundFlow"))

    transactions_in = json_response(result, 200)["data"]["exchangeFundFlow"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "address" => context.address,
             "transactionVolume" => "5000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "address" => context.address,
             "transactionVolume" => "6000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "address" => context.address,
             "transactionVolume" => "9000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "address" => context.address,
             "transactionVolume" => "15000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "address" => context.address,
             "transactionVolume" => "1000"
           } in transactions_in
  end

  test "fetch out transactions", context do
    query = """
    {
      exchangeFundFlow(
        ticker: "#{context.ticker}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        transaction_type: OUT) {
          datetime
          transactionVolume
          address
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundFlow"))

    transactions_out = json_response(result, 200)["data"]["exchangeFundFlow"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "address" => context.address,
             "transactionVolume" => "3000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "address" => context.address,
             "transactionVolume" => "4000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "address" => context.address,
             "transactionVolume" => "18000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "address" => context.address,
             "transactionVolume" => "10000"
           } in transactions_out
  end
end