defmodule SanbaseWeb.Graphql.ApiDelayMiddlewareTest do
  use SanbaseWeb.ConnCase
  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config
  alias SanbaseWeb.Graphql.Middlewares.ApiDelay
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.BurnRate.Store
  alias Sanbase.Auth.User
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

    hour_ago = hour_ago()

    Store.import([
      %Measurement{
        timestamp: hour_ago |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 5000},
        tags: [],
        name: contract_address
      }
    ])

    staked_user =
      %User{
        salt: User.generate_salt(),
        san_balance: Decimal.new(required_san_stake_realtime_api()),
        san_balance_updated_at: Timex.now()
      }
      |> Repo.insert!()

    not_staked_user =
      %User{
        salt: User.generate_salt()
      }
      |> Repo.insert!()

    {:ok, staked_user: staked_user, not_staked_user: not_staked_user}
  end

  test "Does not show real time data for anon users" do
    result =
      build_conn()
      |> post("/graphql", query_skeleton(burnRateQuery(), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    refute %{"burnRate" => 5000.0} in burn_rates
  end

  test "Does not show real for user without SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(burnRateQuery(), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    refute %{"burnRate" => 5000.0} in burn_rates
  end

  test "Shows realtime data if user has SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(burnRateQuery(), "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{"burnRate" => 5000.0} in burn_rates
  end

  defp burnRateQuery() do
    """
    {
      burnRate(
        slug: "santiment",
        from: "#{week_ago()}",
        to: "#{now()}"
        interval: "30m") {
          burnRate
      }
    }
    """
  end

  defp now(), do: Timex.now()
  defp hour_ago(), do: Timex.shift(Timex.now(), hours: -1)
  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)

  defp required_san_stake_realtime_api() do
    Config.module_get(ApiDelay, :required_san_stake_realtime_api) |> String.to_integer()
  end
end
