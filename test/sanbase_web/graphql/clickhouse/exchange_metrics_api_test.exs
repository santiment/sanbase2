defmodule SanbaseWeb.Graphql.ExchangeMetricsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup_with_mocks([
    {Sanbase.Clickhouse.ExchangeAddress, [:passthrough],
     exchange_addresses: fn _ ->
       {:ok,
        [
          %{address: "0x234", name: "Binance", is_dex: false},
          %{address: "0x789", name: "Binance", is_dex: false},
          %{address: "0x567", name: "Bitfinex", is_dex: false}
        ]}
     end},
    {
      Sanbase.Clickhouse.ExchangeAddress,
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
      from: Timex.shift(Timex.now(), days: -10),
      to: Timex.now()
    ]
  end

  test "test all exchanges", context do
    query = ~s/{ allExchanges(slug: "ethereum") }/

    response =
      context.conn
      |> post("/graphql", query_skeleton(query, "allExchanges"))

    exchanges =
      json_response(response, 200)
      |> get_in(["data", "allExchanges"])

    assert Enum.sort(exchanges) == Enum.sort(["Binance", "Bitfinex"])
  end

  describe "top exchanges api" do
    test "get top exchanges by balance", context do
      query = top_exchanges_by_balance(context.project.slug, 10)

      data = [
        %{
          owner: "Binance",
          label: "centralized_exchange",
          balance: 10_000,
          balance_change_1d: 100,
          balance_change_7d: -300,
          balance_change_30d: 1000,
          datetime_of_first_transfers: ~U[2020-01-01 00:00:00Z],
          days: 20
        },
        %{
          owner: "Bitfinex",
          label: "centralized_exchange",
          balance: 20_000,
          balance_change_1d: 20,
          balance_change_7d: -600,
          balance_change_30d: 12_000,
          datetime_of_first_transfers: ~U[2020-01-05 00:00:00Z],
          days: 15
        }
      ]

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Exchanges.top_exchanges_by_balance/3,
        {:ok, data}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = execute_query(context.conn, query, "topExchangesByBalance")

        assert %{
                 "balance" => 1.0e4,
                 "balanceChange1d" => nil,
                 "balanceChange30d" => nil,
                 "balanceChange7d" => nil,
                 "datetimeOfFirstTransfer" => nil,
                 "daysSinceFirstTransfer" => nil,
                 "label" => "centralized_exchange",
                 "owner" => "Binance"
               } in result

        assert %{
                 "balance" => 2.0e4,
                 "balanceChange1d" => nil,
                 "balanceChange30d" => nil,
                 "balanceChange7d" => nil,
                 "datetimeOfFirstTransfer" => nil,
                 "daysSinceFirstTransfer" => nil,
                 "label" => "centralized_exchange",
                 "owner" => "Bitfinex"
               } in result
      end)
    end
  end

  defp top_exchanges_by_balance(slug, limit) do
    """
    {
      topExchangesByBalance(slug: "#{slug}", limit: #{limit}) {
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
