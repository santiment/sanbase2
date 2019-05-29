defmodule SanbaseWeb.Graphql.ExchangesTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]

  setup do
    infr = insert(:infrastructure_eth)

    insert(:exchange_address, %{address: "0x234", name: "Binance", infrastructure_id: infr.id})
    insert(:exchange_address, %{address: "0x567", name: "Bitfinex", infrastructure_id: infr.id})
    insert(:exchange_address, %{address: "0x789", name: "Binance", infrastructure_id: infr.id})

    [
      exchange: "Binance",
      from: from_iso8601!("2017-05-11T00:00:00Z"),
      to: from_iso8601!("2017-05-20T00:00:00Z")
    ]
  end

  test "test all exchanges", context do
    query = "{ allExchanges }"

    response =
      context.conn
      |> post("/graphql", query_skeleton(query, "allExchanges"))

    exchanges = json_response(response, 200)["data"]["allExchanges"]
    assert Enum.sort(exchanges) == Enum.sort(["Binance", "Bitfinex"])
  end

  test "test fetching volume for exchange", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2017-05-13T00:00:00Z"), 2000, 1000],
             [from_iso8601_to_unix!("2017-05-15T00:00:00Z"), 1800, 1300],
             [from_iso8601_to_unix!("2017-05-18T00:00:00Z"), 1000, 1100]
           ]
         }}
      end do
      query =
        exchange_volume_query(
          context.exchange,
          context.from,
          context.to
        )

      response =
        context.conn
        |> post("/graphql", query_skeleton(query, "exchangeVolume"))

      exchanges = json_response(response, 200)["data"]["exchangeVolume"]

      assert exchanges == [
               %{
                 "datetime" => "2017-05-13T00:00:00Z",
                 "exchange_inflow" => 2000,
                 "exchange_outflow" => 1000
               },
               %{
                 "datetime" => "2017-05-15T00:00:00Z",
                 "exchange_inflow" => 1800,
                 "exchange_outflow" => 1300
               },
               %{
                 "datetime" => "2017-05-18T00:00:00Z",
                 "exchange_inflow" => 1000,
                 "exchange_outflow" => 1100
               }
             ]
    end
  end

  defp exchange_volume_query(exchange, from, to) do
    """
      {
        exchangeVolume(
            exchange: "#{exchange}",
            from: "#{from}",
            to: "#{to}",
        ){
            datetime,
            exchange_inflow,
            exchange_outflow
        }
      }
    """
  end
end
