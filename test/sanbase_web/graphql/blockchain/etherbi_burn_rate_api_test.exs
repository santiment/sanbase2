defmodule Sanbase.Etherbi.BurnRateApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  require Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory

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

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00.00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00.00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 22:05:00.00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 22:15:00.00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 22:25:00.00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 22:35:00.00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-13 22:45:00.00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-13 22:55:00.00], "Etc/UTC")

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime1,
      burn_rate: 5000
    })

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime2,
      burn_rate: 1000
    })

    insert(:burn_rate, %{contract_address: contract_address, timestamp: datetime3, burn_rate: 500})

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime4,
      burn_rate: 15000
    })

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime5,
      burn_rate: 65000
    })

    insert(:burn_rate, %{contract_address: contract_address, timestamp: datetime6, burn_rate: 50})
    insert(:burn_rate, %{contract_address: contract_address, timestamp: datetime7, burn_rate: 5})

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime8,
      burn_rate: 5000
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

  test "fetch burn rate when no interval is provided", context do
    query = """
    {
      burnRate(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}") {
          datetime
          burnRate
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert Enum.find(burn_rates, fn %{"burnRate" => burnRate} ->
             burnRate == 6000
           end)

    assert Enum.find(burn_rates, fn %{"burnRate" => burnRate} ->
             burnRate == 85555
           end)
  end

  test "fetch burn rate no aggregation", context do
    query = """
    {
      burnRate(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "5m") {
          datetime
          burnRate
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "burnRate" => 5000.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "burnRate" => 1000.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "burnRate" => 500.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "burnRate" => 15000.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "burnRate" => 65000.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "burnRate" => 50.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "burnRate" => 5.0
           } in burn_rates

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime8),
             "burnRate" => 5000.0
           } in burn_rates
  end

  test "fetch burn rate with aggregation", context do
    query = """
    {
      burnRate(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "30m") {
          datetime
          burnRate
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    # Tests that the datetime is adjusted so it's not before `from`
    assert %{
             "datetime" => "2017-05-13T21:45:00.00Z",
             "burnRate" => 6000.0
           } in burn_rates

    assert %{
             "datetime" => "2017-05-13T22:00:00.00Z",
             "burnRate" => 80500.0
           } in burn_rates

    assert %{
             "datetime" => "2017-05-13T22:30:00.00Z",
             "burnRate" => 5055.0
           } in burn_rates
  end
end
