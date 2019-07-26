defmodule SanbaseWeb.Graphql.TimeframeRestrictionMiddlewareTest do
  use SanbaseWeb.ConnCase
  require Sanbase.Utils.Config, as: Config

  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  alias SanbaseWeb.Graphql.Middlewares.TimeframeRestriction

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory
  require Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  setup do
    contract = "0x132123"
    # Both projects use the have same contract address for easier testing.
    # Accessing through the slug that is not "santiment" has timeframe restriction
    # while accessing through "santiment" does not
    p1 =
      Sanbase.Factory.insert(:random_erc20_project, %{
        coinmarketcap_id: "santiment",
        main_contract_address: contract
      })

    p2 = Sanbase.Factory.insert(:random_erc20_project, %{main_contract_address: contract})

    %{user: user} =
      Sanbase.Factory.insert(:subscription_premium, user: Sanbase.Factory.insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    insert(:transaction_volume, %{
      contract_address: contract,
      timestamp: hour_ago(),
      transaction_volume: 5000
    })

    insert(:transaction_volume, %{
      contract_address: contract,
      timestamp: week_ago(),
      transaction_volume: 6000
    })

    insert(:transaction_volume, %{
      contract_address: contract,
      timestamp: restricted_from(),
      transaction_volume: 7000
    })

    [
      conn: conn,
      santiment_slug: p1.coinmarketcap_id,
      not_santiment_slug: p2.coinmarketcap_id
    ]
  end

  test "`from` later than `to` datetime", context do
    query = """
     {
      transactionVolume(
        slug: "santiment",
        from: "#{Timex.now()}",
        to: "#{Timex.shift(Timex.now(), days: -10)}"
        interval: "30m") {
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    %{
      "errors" => [
        %{
          "message" => error_message
        }
      ]
    } = result

    assert error_message ==
             "The `to` datetime parameter must be after the `from` datetime parameter\n"
  end

  test "returns error when `from` param is before 2009 year", context do
    query = """
     {
      transactionVolume(
        slug: "santiment",
        from: "#{from_iso8601!("2008-12-31T23:59:59Z")}",
        to: "#{from_iso8601!("2009-01-02T00:00:00Z")}"
        interval: "1d") {
          datetime
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))

    error = List.first(json_response(result, 200)["errors"])["message"]

    assert error ==
             "Cryptocurrencies didn't existed before 2009-01-01 00:00:00Z.\nPlease check `from` and/or `to` param values.\n"
  end

  test "returns error when `from` and `to` params are both before 2009 year", context do
    query = """
     {
      transactionVolume(
        slug: "santiment",
        from: "#{from_iso8601!("2008-12-30T23:59:59Z")}",
        to: "#{from_iso8601!("2008-12-31T23:59:59Z")}"
        interval: "1d") {
          datetime
          transactionVolume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))

    error = List.first(json_response(result, 200)["errors"])["message"]

    assert error ==
             "Cryptocurrencies didn't existed before 2009-01-01 00:00:00Z.\nPlease check `from` and/or `to` param values.\n"
  end

  defp hour_ago(), do: Timex.shift(Timex.now(), hours: -1)
  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)
  defp restricted_from(), do: Timex.shift(Timex.now(), days: restrict_from_in_days() - 1)

  defp restrict_from_in_days do
    -1 *
      (Config.module_get(TimeframeRestriction, :restrict_from_in_days) |> String.to_integer())
  end
end
