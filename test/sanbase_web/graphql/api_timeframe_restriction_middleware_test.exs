defmodule SanbaseWeb.Graphql.ApiTimeframeRestrictionMiddlewareTest do
  use SanbaseWeb.ConnCase
  require Sanbase.Utils.Config, as: Config

  alias SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.BurnRate
  alias Sanbase.Etherbi.DailyActiveAddresses
  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    BurnRate.Store.create_db()
    DailyActiveAddresses.Store.create_db()

    ticker = "SAN"
    san_slug = "santiment"
    not_san_slug = "some_other_name"

    contract_address = "0x1234"
    BurnRate.Store.drop_measurement(contract_address)
    DailyActiveAddresses.Store.drop_measurement(contract_address)

    %Project{
      name: "Santiment",
      ticker: ticker,
      coinmarketcap_id: san_slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    %Project{
      name: "Santiment",
      ticker: ticker,
      coinmarketcap_id: not_san_slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    BurnRate.Store.import([
      %Measurement{
        timestamp: hour_ago() |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 5000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: week_ago() |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 6000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: restricted_from() |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 7000},
        tags: [],
        name: contract_address
      }
    ])

    DailyActiveAddresses.Store.import([
      %Measurement{
        timestamp: hour_ago() |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 100},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: week_ago() |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 200},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: restricted_from() |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 300},
        tags: [],
        name: contract_address
      }
    ])

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

    {:ok,
     staked_user: staked_user,
     not_staked_user: not_staked_user,
     santiment_slug: san_slug,
     not_santiment_slug: not_san_slug}
  end

  test "does not show real time data and data before certain period to anon users", context do
    result =
      build_conn()
      |> post("/graphql", query_skeleton(burnRateQuery(context.not_santiment_slug), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    refute %{"burnRate" => 5000.0} in burn_rates
    assert %{"burnRate" => 6000.0} in burn_rates
    refute %{"burnRate" => 7000.0} in burn_rates
  end

  # The Santiment project treatment is special. It serves the purpose of showing how
  # the data looks like as if you have staked.
  test "shows real time data and data before certain period to anon users for Santiment project",
       context do
    result =
      build_conn()
      |> post("/graphql", query_skeleton(burnRateQuery(context.santiment_slug), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{"burnRate" => 5000.0} in burn_rates
    assert %{"burnRate" => 6000.0} in burn_rates
    assert %{"burnRate" => 7000.0} in burn_rates
  end

  test "does not show real for user without SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(burnRateQuery(context.not_santiment_slug), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    refute %{"burnRate" => 5000.0} in burn_rates
    assert %{"burnRate" => 6000.0} in burn_rates
    refute %{"burnRate" => 7000.0} in burn_rates
  end

  test "shows real for user without SAN stake for Santiment project", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(burnRateQuery(context.santiment_slug), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{"burnRate" => 5000.0} in burn_rates
    assert %{"burnRate" => 6000.0} in burn_rates
    assert %{"burnRate" => 7000.0} in burn_rates
  end

  test "shows realtime data if user has SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(burnRateQuery(context.not_santiment_slug), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{"burnRate" => 5000.0} in burn_rates
    assert %{"burnRate" => 6000.0} in burn_rates
    assert %{"burnRate" => 7000.0} in burn_rates
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

  defp burnRateQuery(slug) do
    """
    {
      burnRate(
        slug: "#{slug}",
        from: "#{before_restricted_from()}",
        to: "#{now()}"
        interval: "30m") {
          burnRate
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
