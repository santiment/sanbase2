defmodule Sanbase.Etherbi.TokenAgeConsumedApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

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

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-14 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-14 22:15:00], "Etc/UTC")

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime1,
      burn_rate: 5_000_000
    })

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime2,
      burn_rate: 3_640_000
    })

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime3,
      burn_rate: 10_000
    })

    insert(:burn_rate, %{
      contract_address: contract_address,
      timestamp: datetime4,
      burn_rate: 7_280
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime1,
      transaction_volume: 15
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime2,
      transaction_volume: 5
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime3,
      transaction_volume: 20
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime4,
      transaction_volume: 10
    })

    [
      slug: slug,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      conn: conn
    ]
  end

  test "fetch token age consumed in days", context do
    query = """
    {
      tokenAgeConsumedInDays(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime4}",
        interval: "1d") {
          datetime
          tokenAge
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenAgeConsumedInDays"))

    token_age_consumed_in_days = json_response(result, 200)["data"]["tokenAgeConsumedInDays"]

    assert %{
             "datetime" => "2017-05-13T21:45:00Z",
             "tokenAge" => 75.0
           } in token_age_consumed_in_days

    assert %{
             "datetime" => "2017-05-14T00:00:00Z",
             "tokenAge" => 0.1
           } in token_age_consumed_in_days
  end
end
