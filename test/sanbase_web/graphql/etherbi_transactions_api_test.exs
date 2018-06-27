defmodule Sanbase.Etherbi.TransactionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.Transactions.Store
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    slug = "santiment"
    exchange_address = "0x4321"
    contract_address = "0x1234"
    Store.drop_measurement(contract_address)

    project =
      %Project{
        name: "Santiment",
        ticker: ticker,
        coinmarketcap_id: slug,
        main_contract_address: contract_address
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 00:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 00:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 00:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 00:00:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-19 00:00:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-20 00:00:00], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{incoming_exchange_funds: 5000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        # datetime 1: total 2000 in
        fields: %{outgoing_exchange_funds: 3000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        # datetime 2: total 2000 in
        fields: %{incoming_exchange_funds: 6000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{outgoing_exchange_funds: 4000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        # datetime 3: total 9000 in
        fields: %{incoming_exchange_funds: 9000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        # datetime 4: total 15000 in
        fields: %{incoming_exchange_funds: 15000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        # datetime 5: total 18000 out
        fields: %{outgoing_exchange_funds: 18000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        # datetime 6: total 1000 in
        fields: %{incoming_exchange_funds: 1000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{outgoing_exchange_funds: 10000},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        # datetime 7: total 8450 out
        fields: %{incoming_exchange_funds: 1550},
        name: contract_address
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        # datetime 8; total 50000 out
        fields: %{outgoing_exchange_funds: 50000},
        name: contract_address
      }
    ])

    [
      exchange_address: exchange_address,
      slug: slug,
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

  test "fetch funds flow when no interval is provided", context do
    query = """
    {
      exchangeFundsFlow(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}") {
          datetime
          fundsFlow
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))

    funds_flow_list = json_response(result, 200)["data"]["exchangeFundsFlow"]

    assert Enum.find(funds_flow_list, fn %{"fundsFlow" => fundsFlow} ->
             fundsFlow == 2000
           end)
  end

  test "fetch funds flow", context do
    query = """
    {
      exchangeFundsFlow(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "1d") {
          datetime
          fundsFlow
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))

    funds_flow_list = json_response(result, 200)["data"]["exchangeFundsFlow"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "fundsFlow" => 2000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "fundsFlow" => 2000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "fundsFlow" => 9000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "fundsFlow" => 15000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "fundsFlow" => -18000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "fundsFlow" => 1000
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "fundsFlow" => -8450
           } in funds_flow_list

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime8),
             "fundsFlow" => -50000
           } in funds_flow_list
  end
end
