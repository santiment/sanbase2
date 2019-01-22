defmodule SanbaseWeb.Graphql.Blockchain.TokenVelocityApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  require Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory
  import ExUnit.CaptureLog

  setup do
    ticker = "SAN"
    slug = "santiment"
    contract_address = "0x1234"

    staked_user = Sanbase.Factory.insert(:staked_user)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: ticker,
      coinmarketcap_id: slug,
      main_contract_address: contract_address
    })

    conn = setup_jwt_auth(build_conn(), staked_user)

    datetime_start = DateTime.from_naive!(~N[2019-01-10 00:00:00], "Etc/UTC")
    datetime1 = DateTime.from_naive!(~N[2019-01-11 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2019-01-12 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2019-01-13 00:00:00], "Etc/UTC")
    datetime_end = DateTime.from_naive!(~N[2019-01-15 00:00:00], "Etc/UTC")

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime1,
      less_than_a_day: 1000.0
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime2,
      less_than_a_day: 0.0
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime3,
      less_than_a_day: 2000.0
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime1,
      transaction_volume: 1000.0
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime2,
      transaction_volume: 100.0
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime3,
      transaction_volume: 3000.0
    })

    [
      slug: slug,
      conn: conn,
      datetime_start: datetime_start,
      datetime_end: datetime_end
    ]
  end

  test "fetch token velocity", context do
    query = """
    {
      tokenVelocity(
        slug: "#{context.slug}",
        from: "#{context.datetime_start}",
        to: "#{context.datetime_end}",
        interval: "1d"
      ) {
        datetime
        tokenVelocity
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenVelocity"))

    result = json_response(result, 200)["data"]["tokenVelocity"]

    assert %{
             "datetime" => "2019-01-11T00:00:00Z",
             "tokenVelocity" => 1.0
           } in result

    assert %{
             "datetime" => "2019-01-12T00:00:00Z",
             "tokenVelocity" => 0.0
           } in result

    assert %{
             "datetime" => "2019-01-13T00:00:00Z",
             "tokenVelocity" => 1.50
           } in result
  end

  test "fetch token velocity without full day interval", context do
    query = """
    {
      tokenVelocity(
        slug: "#{context.slug}",
        from: "#{context.datetime_start}",
        to: "#{context.datetime_end}",
        interval: "25h"
      ) {
        datetime
        tokenVelocity
      }
    }
    """

    assert capture_log(fn ->
             context.conn
             |> post("/graphql", query_skeleton(query, "tokenVelocity"))
           end) =~ "The interval must consist of whole days"
  end
end
