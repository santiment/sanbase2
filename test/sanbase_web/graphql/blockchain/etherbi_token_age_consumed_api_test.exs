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
    datetime3 = DateTime.from_naive!(~N[2017-05-13 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 22:15:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 22:25:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 22:35:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-13 22:45:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-13 22:55:00], "Etc/UTC")

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime1,
      token_age_consumed: 5000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime2,
      token_age_consumed: 1000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime3,
      token_age_consumed: 500
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime4,
      token_age_consumed: 15000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime5,
      token_age_consumed: 65000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime6,
      token_age_consumed: 50
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime7,
      token_age_consumed: 5
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime8,
      token_age_consumed: 5000
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
      tokenAgeConsumed(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "") {
          datetime
          tokenAgeConsumed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    assert Enum.find(token_age_consumed, fn %{"tokenAgeConsumed" => tokenAgeConsumed} ->
             tokenAgeConsumed == 6000
           end)

    assert Enum.find(token_age_consumed, fn %{"tokenAgeConsumed" => tokenAgeConsumed} ->
             tokenAgeConsumed == 85555
           end)
  end

  test "fetch burn rate no aggregation", context do
    query = """
    {
      tokenAgeConsumed(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "5m") {
          datetime
          tokenAgeConsumed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "tokenAgeConsumed" => 5000.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "tokenAgeConsumed" => 1000.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "tokenAgeConsumed" => 500.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "tokenAgeConsumed" => 15000.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "tokenAgeConsumed" => 65000.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "tokenAgeConsumed" => 50.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "tokenAgeConsumed" => 5.0
           } in token_age_consumed

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime8),
             "tokenAgeConsumed" => 5000.0
           } in token_age_consumed
  end

  test "fetch burn rate with aggregation", context do
    query = """
    {
      tokenAgeConsumed(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "30m") {
          datetime
          tokenAgeConsumed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    # Tests that the datetime is adjusted so it's not before `from`
    assert %{
             "datetime" => "2017-05-13T21:45:00Z",
             "tokenAgeConsumed" => 6000.0
           } in token_age_consumed

    assert %{
             "datetime" => "2017-05-13T22:00:00Z",
             "tokenAgeConsumed" => 80500.0
           } in token_age_consumed

    assert %{
             "datetime" => "2017-05-13T22:30:00Z",
             "tokenAgeConsumed" => 5055.0
           } in token_age_consumed
  end
end
