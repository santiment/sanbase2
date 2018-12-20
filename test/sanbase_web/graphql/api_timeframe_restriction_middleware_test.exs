defmodule SanbaseWeb.Graphql.ApiTimeframeRestrictionMiddlewareTest do
  use SanbaseWeb.ConnCase
  require Sanbase.Utils.Config, as: Config

  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  alias SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction
  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory

  setup do
    san_slug = "santiment"
    not_san_slug = "some_other_name"

    contract_address = "0x12345"

    # Both projects use the have same contract address for easier testing.
    # Accessing through the slug that is not "santiment" has timeframe restriction
    # while accessing through "santiment" does not
    %Project{
      name: "Santiment",
      coinmarketcap_id: san_slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    %Project{
      name: "Santiment2",
      coinmarketcap_id: not_san_slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: hour_ago(),
      token_age_consumed: 5000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: week_ago(),
      token_age_consumed: 6000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: restricted_from(),
      token_age_consumed: 7000
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: hour_ago(),
      active_addresses: 100
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: week_ago(),
      active_addresses: 200
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: restricted_from(),
      active_addresses: 300
    })

    staked_user =
      %User{
        salt: User.generate_salt(),
        san_balance: Decimal.new(required_san_stake_full_access()),
        san_balance_updated_at: Timex.now()
      }
      |> Repo.insert!()

    not_staked_user =
      %User{
        salt: User.generate_salt()
      }
      |> Repo.insert!()

    [
      staked_user: staked_user,
      not_staked_user: not_staked_user,
      santiment_slug: san_slug,
      not_santiment_slug: not_san_slug
    ]
  end

  test "does not show real time data and data before certain period to anon users", context do
    result =
      build_conn()
      |> post(
        "/graphql",
        query_skeleton(tokenAgeConsumedQuery(context.not_santiment_slug), "tokenAgeConsumed")
      )

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    refute %{"tokenAgeConsumed" => 5000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 6000.0} in token_age_consumed
    refute %{"tokenAgeConsumed" => 7000.0} in token_age_consumed
  end

  # The Santiment project treatment is special. It serves the purpose of showing how
  # the data looks like as if you have staked.
  test "shows real time data and data before certain period to anon users for Santiment project",
       context do
    result =
      build_conn()
      |> post(
        "/graphql",
        query_skeleton(tokenAgeConsumedQuery(context.santiment_slug), "tokenAgeConsumed")
      )

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    assert %{"tokenAgeConsumed" => 5000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 6000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 7000.0} in token_age_consumed
  end

  test "does not show real for user without SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post(
        "/graphql",
        query_skeleton(tokenAgeConsumedQuery(context.not_santiment_slug), "tokenAgeConsumed")
      )

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    refute %{"tokenAgeConsumed" => 5000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 6000.0} in token_age_consumed
    refute %{"tokenAgeConsumed" => 7000.0} in token_age_consumed
  end

  test "shows real for user without SAN stake for Santiment project", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post(
        "/graphql",
        query_skeleton(tokenAgeConsumedQuery(context.santiment_slug), "tokenAgeConsumed")
      )

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    assert %{"tokenAgeConsumed" => 5000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 6000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 7000.0} in token_age_consumed
  end

  test "shows realtime data if user has SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.staked_user)

    result =
      conn
      |> post(
        "/graphql",
        query_skeleton(tokenAgeConsumedQuery(context.not_santiment_slug), "tokenAgeConsumed")
      )

    token_age_consumed = json_response(result, 200)["data"]["tokenAgeConsumed"]

    assert %{"tokenAgeConsumed" => 5000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 6000.0} in token_age_consumed
    assert %{"tokenAgeConsumed" => 7000.0} in token_age_consumed
  end

  test "shows historical data but not realtime for DAA", context do
    result =
      build_conn()
      |> post(
        "/graphql",
        query_skeleton(
          dailyActiveAddressesQuery(context.not_santiment_slug),
          "dailyActiveAddresses"
        )
      )

    daas = json_response(result, 200)["data"]["dailyActiveAddresses"]

    refute %{"activeAddresses" => 100} in daas
    assert %{"activeAddresses" => 200} in daas
    assert %{"activeAddresses" => 300} in daas
  end

  defp tokenAgeConsumedQuery(slug) do
    """
    {
      tokenAgeConsumed(
        slug: "#{slug}",
        from: "#{before_restricted_from()}",
        to: "#{now()}"
        interval: "30m") {
          tokenAgeConsumed
      }
    }
    """
  end

  defp dailyActiveAddressesQuery(slug) do
    """
    {
      dailyActiveAddresses(
        slug: "#{slug}",
        from: "#{before_restricted_from()}",
        to: "#{now()}") {
          activeAddresses
      }
    }
    """
  end

  defp now(), do: Timex.now()
  defp hour_ago(), do: Timex.shift(Timex.now(), hours: -1)
  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)
  defp restricted_from(), do: Timex.shift(Timex.now(), days: restrict_from_in_days() - 1)
  defp before_restricted_from(), do: Timex.shift(Timex.now(), days: restrict_from_in_days() - 2)

  defp required_san_stake_full_access() do
    Config.module_get(ApiTimeframeRestriction, :required_san_stake_full_access)
    |> String.to_integer()
  end

  defp restrict_from_in_days do
    -1 *
      (Config.module_get(ApiTimeframeRestriction, :restrict_from_in_days) |> String.to_integer())
  end
end
