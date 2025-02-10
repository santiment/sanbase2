defmodule SanbaseWeb.Graphql.ExchangeMetricsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.ExchangeAddress

  setup_with_mocks([
    {ExchangeAddress, [:passthrough],
     exchange_addresses: fn _ ->
       {:ok,
        [
          %{address: "0x234", name: "Binance", is_dex: false},
          %{address: "0x789", name: "Binance", is_dex: false},
          %{address: "0x567", name: "Bitfinex", is_dex: false}
        ]}
     end},
    {
      ExchangeAddress,
      [:passthrough],
      exchange_names: fn _, _ -> {:ok, ["Binance", "Bitfinex"]} end
    }
  ]) do
    []
  end

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    project = insert(:random_project)

    [
      exchange: "Binance",
      project: project,
      conn: conn,
      from: Timex.shift(DateTime.utc_now(), days: -10),
      to: DateTime.utc_now()
    ]
  end

  test "test all exchanges", context do
    query = ~s/{ allExchanges(slug: "ethereum") }/

    response = post(context.conn, "/graphql", query_skeleton(query, "allExchanges"))

    exchanges =
      response
      |> json_response(200)
      |> get_in(["data", "allExchanges"])

    assert Enum.sort(exchanges) == Enum.sort(["Binance", "Bitfinex"])
  end

  describe "top exchanges api" do
    test "get top exchanges by balance", context do
      query = top_exchanges_by_balance(context.project.slug, 10)
      dt = ~U[2024-05-01 00:00:00Z]
      now = DateTime.utc_now()

      rows = [
        [
          "binance",
          "santiment/centralized_exchange:v1",
          10_000.0,
          100.0,
          -300.0,
          1000.0,
          DateTime.to_unix(dt)
        ],
        [
          "bitfinex",
          "santiment/centralized_exchange:v1",
          20_000.0,
          20.0,
          -600.0,
          12_000.0,
          DateTime.to_unix(dt)
        ]
      ]

      (&Sanbase.ClickhouseRepo.query/2)
      |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = execute_query(context.conn, query, "topExchangesByBalance")

        assert %{
                 "label" => "santiment/centralized_exchange:v1",
                 "owner" => "binance",
                 "balance" => 10_000.0,
                 "balanceChange1d" => 100.0,
                 "balanceChange7d" => -300.0,
                 "balanceChange30d" => 1000.0,
                 "datetimeOfFirstTransfer" => DateTime.to_iso8601(dt),
                 "daysSinceFirstTransfer" => dt |> DateTime.diff(now, :day) |> abs()
               } in result

        assert %{
                 "balance" => 20_000.0,
                 "balanceChange1d" => 20.0,
                 "balanceChange7d" => -600.0,
                 "balanceChange30d" => 12_000.0,
                 "datetimeOfFirstTransfer" => DateTime.to_iso8601(dt),
                 "daysSinceFirstTransfer" => dt |> DateTime.diff(now, :day) |> abs(),
                 "label" => "santiment/centralized_exchange:v1",
                 "owner" => "bitfinex"
               } in result
      end)
    end
  end

  defp top_exchanges_by_balance(slug, limit) do
    """
    {
      topExchangesByBalance(slug: "#{slug}" limit: #{limit}) {
        owner
        label
        balance
        balanceChange1d
        balanceChange7d
        balanceChange30d
        datetimeOfFirstTransfer
        daysSinceFirstTransfer
      }
    }
    """
  end
end
