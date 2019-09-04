defmodule Sanbase.Etherbi.TransactionVolumeApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  require Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory

  setup do
    %{user: user} =
      Sanbase.Factory.insert(:subscription_pro_sanbase, user: Sanbase.Factory.insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    %{
      slug: slug,
      main_contract_address: contract_address,
      token_decimals: token_decimals
    } = Sanbase.Factory.insert(:random_erc20_project)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 22:15:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 22:25:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 22:35:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-13 22:45:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-13 22:55:00], "Etc/UTC")

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime1,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 1000
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime2,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 555
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime3,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 123
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime4,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 6643
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime5,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 64123
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime6,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 1232
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime7,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 555
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime8,
      transaction_volume: Sanbase.Math.ipow(10, token_decimals) * 12111
    })

    [
      slug: slug,
      from: datetime1,
      to: datetime8,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      datetime5: datetime5,
      datetime6: datetime6,
      datetime7: datetime7,
      datetime8: datetime8,
      conn: conn
    ]
  end

  test "fetch transaction volume when no interval is provided", context do
    query = """
    {
      transactionVolume(
        slug: "#{context.slug}",
        from: "#{context.from}",
        to: "#{context.to}",
        interval: "") {
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
        from: "#{context.from}",
        to: "#{context.to}",
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
