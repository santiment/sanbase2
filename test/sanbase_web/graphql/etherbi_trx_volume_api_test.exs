defmodule Sanbase.Etherbi.TransactionVolumeApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.TransactionVolume.Store
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    slug = "santiment"
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

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 22:15:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 22:25:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 22:35:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-13 22:45:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-13 22:55:00], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 1000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 555},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 123},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 6643},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 64123},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 1232},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 555},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: 12111},
        tags: [],
        name: contract_address
      }
    ])

    [
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

  test "fetch transaction volume when no interval is provided", context do
    query = """
    {
      transactionVolume(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}") {
          datetime
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactionVolume"))

    trx_volumes = json_response(result, 200)["data"]["transactionVolume"]

    assert Enum.find(trx_volumes, fn %{"transactionVolume" => transactionVolume} ->
             transactionVolume == 1555
           end)

    assert Enum.find(trx_volumes, fn %{"transactionVolume" => transactionVolume} ->
             transactionVolume == 84787
           end)
  end

  test "fetch transaction volume no aggregation", context do
    query = """
    {
      transactionVolume(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "5m") {
          datetime
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactionVolume"))

    trx_volumes = json_response(result, 200)["data"]["transactionVolume"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "transactionVolume" => 1000.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "transactionVolume" => 555.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "transactionVolume" => 123.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "transactionVolume" => 6643.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "transactionVolume" => 64123.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "transactionVolume" => 1232.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "transactionVolume" => 555.0
           } in trx_volumes

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime8),
             "transactionVolume" => 12111.0
           } in trx_volumes
  end

  test "fetch transaction volume with aggregation", context do
    query = """
    {
      transactionVolume(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "15m") {
          datetime
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactionVolume"))

    trx_volumes = json_response(result, 200)["data"]["transactionVolume"]

    assert %{
             "datetime" => "2017-05-13T21:45:00Z",
             "transactionVolume" => 1555.0
           } in trx_volumes

    assert %{
             "datetime" => "2017-05-13T22:00:00Z",
             "transactionVolume" => 123.0
           } in trx_volumes

    assert %{
             "datetime" => "2017-05-13T22:15:00Z",
             "transactionVolume" => 70766.0
           } in trx_volumes

    assert %{
             "datetime" => "2017-05-13T22:30:00Z",
             "transactionVolume" => 1232.0
           } in trx_volumes

    assert %{
             "datetime" => "2017-05-13T22:45:00Z",
             "transactionVolume" => 12666.0
           } in trx_volumes
  end
end
