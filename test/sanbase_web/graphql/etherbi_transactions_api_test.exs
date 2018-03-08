defmodule Sanbase.Etherbi.TransactionsApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.Transactions.Store
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    exchange_address = "0x4321"
    contract_address = "0x1234"
    Store.drop_measurement(contract_address)

    project =
      %Project{name: "Santiment", ticker: ticker}
      |> Repo.insert!()

    %Ico{project_id: project.id, main_contract_address: contract_address}
    |> Repo.insert!()

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
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "3000", ticker: ticker},
        tags: [transaction_type: "out", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "6000", ticker: ticker},
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "4000", ticker: ticker},
        tags: [transaction_type: "out", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "9000", ticker: ticker},
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "15000", ticker: ticker},
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "18000", ticker: ticker},
        tags: [transaction_type: "out", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "1000", ticker: ticker},
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "10000", ticker: ticker},
        tags: [transaction_type: "out", address: exchange_address],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "50000", ticker: ticker},
        tags: [transaction_type: "in", address: exchange_address],
        name: contract_address
      }
    ])

    [
      exchange_address: exchange_address,
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
             "address" => context.exchange_address,
             "transactionVolume" => "5000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "address" => context.exchange_address,
             "transactionVolume" => "6000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "address" => context.exchange_address,
             "transactionVolume" => "9000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "address" => context.exchange_address,
             "transactionVolume" => "15000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "address" => context.exchange_address,
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
             "address" => context.exchange_address,
             "transactionVolume" => "3000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "address" => context.exchange_address,
             "transactionVolume" => "4000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "address" => context.exchange_address,
             "transactionVolume" => "18000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "address" => context.exchange_address,
             "transactionVolume" => "10000"
           } in transactions_out
  end
end
