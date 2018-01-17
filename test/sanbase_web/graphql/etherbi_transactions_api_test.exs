defmodule Sanbase.Github.EtherbiTransactionsApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.Store

  setup do
    Store.create_db()

    wallet = "0x12345678"
    Store.drop_measurement(wallet)

    token = "SAN"

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
        fields: %{volume: "5000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "3000", token: token},
        tags: [transaction_type: "out"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "6000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "4000", token: token},
        tags: [transaction_type: "out"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "9000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "15000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "18000", token: token},
        tags: [transaction_type: "out"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "1000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "10000", token: token},
        tags: [transaction_type: "out"],
        name: wallet
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: "50000", token: token},
        tags: [transaction_type: "in"],
        name: wallet
      }
    ])

    [
      wallet: wallet,
      token: token,
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
      transactions(
        wallet: "#{context.wallet}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        transaction_type: "in") {
          datetime
          transactionVolume
          token
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactions"))

    transactions_in = json_response(result, 200)["data"]["transactions"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "token" => context.token,
             "transactionVolume" => "5000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "token" => context.token,
             "transactionVolume" => "6000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "token" => context.token,
             "transactionVolume" => "9000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "token" => context.token,
             "transactionVolume" => "15000"
           } in transactions_in

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "token" => context.token,
             "transactionVolume" => "1000"
           } in transactions_in
  end

  test "fetch out transactions", context do
    query = """
    {
      transactions(
        wallet: "#{context.wallet}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        transaction_type: "out") {
          datetime
          transactionVolume
          token
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactions"))

    transactions_out = json_response(result, 200)["data"]["transactions"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "token" => context.token,
             "transactionVolume" => "3000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "token" => context.token,
             "transactionVolume" => "4000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "token" => context.token,
             "transactionVolume" => "18000"
           } in transactions_out

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "token" => context.token,
             "transactionVolume" => "10000"
           } in transactions_out
  end

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end
end