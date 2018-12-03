defmodule Sanbase.Etherbi.TokenCirculationApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  require Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory
  import ExUnit.CaptureLog

  setup do
    staked_user = Sanbase.Factory.insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), staked_user)

    ticker = "SAN"
    slug = "santiment"
    contract_address = "0x1234"

    %Project{
      name: "Santiment",
      ticker: ticker,
      coinmarketcap_id: slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 22:15:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-14 22:25:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-14 22:35:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-14 22:45:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-14 22:55:00], "Etc/UTC")

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime1,
      less_than_a_day: 5000
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime2,
      less_than_a_day: 1000
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime3,
      less_than_a_day: 500
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime4,
      less_than_a_day: 15000
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime5,
      less_than_a_day: 65000
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime6,
      less_than_a_day: 50
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime7,
      less_than_a_day: 5
    })

    insert(:token_circulation, %{
      contract_address: contract_address,
      timestamp: datetime8,
      less_than_a_day: 5000
    })

    [
      slug: slug,
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

  test "fetch token circulation", context do
    query = """
    {
      tokenCirculation(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "1d") {
          datetime
          tokenCirculation
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenCirculation"))

    token_circulation = json_response(result, 200)["data"]["tokenCirculation"]

    assert %{
             "datetime" => "2017-05-13T21:45:00Z",
             "tokenCirculation" => 21500.0
           } in token_circulation

    assert %{
             "datetime" => "2017-05-14T00:00:00Z",
             "tokenCirculation" => 70055.0
           } in token_circulation
  end

  test "fetch token circulation for interval that doesn't consist of full days", context do
    query = """
    {
      tokenCirculation(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "25h") {
          datetime
          tokenCirculation
      }
    }
    """

    assert capture_log(fn ->
             context.conn
             |> post("/graphql", query_skeleton(query, "tokenCirculation"))
           end) =~ "The interval must consist of whole days"
  end
end
