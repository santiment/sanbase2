defmodule SanbaseWeb.Graphql.ProjectApiFundsRaisedTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Utils.Config, only: [parse_config_value: 1]
  import Sanbase.Factory

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    # Add the Projects to the Postgres
    insert(:project, %{name: "Test project", coinmarketcap_id: "test", ticker: "TEST"})
    insert(:project, %{name: "Bitcoin", coinmarketcap_id: "bitcoin", ticker: "BTC"})
    insert(:project, %{name: "Ethereum", coinmarketcap_id: "ethereum", ticker: "ETH"})

    # Initialize the Influxdb state
    test_ticker_cmc_id = "TEST_test"
    btc_ticker_cmc_id = "BTC_bitcoin"
    eth_ticker_cmc_id = "ETH_ethereum"

    Store.drop_measurement(test_ticker_cmc_id)
    Store.drop_measurement(btc_ticker_cmc_id)
    Store.drop_measurement(eth_ticker_cmc_id)

    date1 = "2017-08-19"
    {:ok, dt1} = Timex.parse!(date1, "{YYYY}-{0M}-{D}") |> DateTime.from_naive("Etc/UTC")
    date1_unix = dt1 |> DateTime.to_unix(:nanosecond)

    date2 = "2017-10-17"
    {:ok, dt2} = Timex.parse!(date2, "{YYYY}-{0M}-{D}") |> DateTime.from_naive("Etc/UTC")
    date2_unix = dt2 |> DateTime.to_unix(:nanosecond)

    Store.import([
      %Measurement{
        timestamp: date1_unix,
        fields: %{price_usd: 2, volume_usd: 200, marketcap_usd: 500},
        name: btc_ticker_cmc_id
      },
      %Measurement{
        timestamp: date1_unix,
        fields: %{price_usd: 4, volume_usd: 200, marketcap_usd: 500},
        name: test_ticker_cmc_id
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price_usd: 5, volume_usd: 200, marketcap_usd: 500},
        name: btc_ticker_cmc_id
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price_usd: 10, volume_usd: 200, marketcap_usd: 500},
        name: eth_ticker_cmc_id
      }
    ])

    # Add the 3 currencies
    currency_eth = insert(:currency, %{code: "ETH"})
    currency_btc = insert(:currency, %{code: "BTC"})
    currency = insert(:currency, %{code: "TEST"})

    # Add a random project and its ICOs
    project =
      insert(:project, %{name: rand_str(), coinmarketcap_id: rand_str(), ticker: rand_str(4)})

    ico1 = insert(:ico, %{project_id: project.id, end_date: date1})
    insert(:ico_currency, %{ico_id: ico1.id, currency_id: currency_eth.id, amount: 150})
    insert(:ico_currency, %{ico_id: ico1.id, currency_id: currency.id, amount: 50})

    ico2 = insert(:ico, %{project_id: project.id, end_date: date2})
    insert(:ico_currency, %{ico_id: ico2.id, currency_id: currency_btc.id, amount: 200})

    project_no_ico =
      insert(:project, %{name: rand_str(), coinmarketcap_id: rand_str(), ticker: rand_str(4)})

    [
      project: project,
      project_no_ico: project_no_ico
    ]
  end

  test "fetch project public funds raised", context do
    project = context.project

    query = """
    {
      project(id: $id) {
        name,
        fundsRaisedUsdIcoEndPrice,
        fundsRaisedEthIcoEndPrice,
        fundsRaisedBtcIcoEndPrice
      }
    }
    """

    result =
      context.conn
      |> post(
        "/graphql",
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project.id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => project.name,
               "fundsRaisedUsdIcoEndPrice" => 1200.0,
               "fundsRaisedEthIcoEndPrice" => 250.0,
               "fundsRaisedBtcIcoEndPrice" => 300.0
             }
  end

  test "fetch project funds raised", context do
    project = context.project

    query = """
    {
      project(id: $id) {
        name,
        fundsRaisedUsdIcoEndPrice,
        fundsRaisedEthIcoEndPrice,
        fundsRaisedBtcIcoEndPrice,
        icos {
          endDate,
          fundsRaisedUsdIcoEndPrice,
          fundsRaisedEthIcoEndPrice,
          fundsRaisedBtcIcoEndPrice
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post(
        "/graphql",
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project.id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => project.name,
               "fundsRaisedUsdIcoEndPrice" => 1200.0,
               "fundsRaisedEthIcoEndPrice" => 250.0,
               "fundsRaisedBtcIcoEndPrice" => 300.0,
               "icos" => [
                 %{
                   "endDate" => "2017-08-19",
                   "fundsRaisedUsdIcoEndPrice" => 200.0,
                   "fundsRaisedEthIcoEndPrice" => 150.0,
                   "fundsRaisedBtcIcoEndPrice" => 100.0
                 },
                 %{
                   "endDate" => "2017-10-17",
                   "fundsRaisedUsdIcoEndPrice" => 1000.0,
                   "fundsRaisedEthIcoEndPrice" => 100.0,
                   "fundsRaisedBtcIcoEndPrice" => 200.0
                 }
               ]
             }
  end

  test "no ico does not break query", context do
    project = context.project_no_ico

    query = """
    {
      project(id: $id) {
        name,
        fundsRaisedUsdIcoEndPrice,
        fundsRaisedEthIcoEndPrice,
        fundsRaisedBtcIcoEndPrice,
        icos {
          endDate,
          fundsRaisedUsdIcoEndPrice,
          fundsRaisedEthIcoEndPrice,
          fundsRaisedBtcIcoEndPrice
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post(
        "/graphql",
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project.id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => project.name,
               "fundsRaisedUsdIcoEndPrice" => nil,
               "fundsRaisedEthIcoEndPrice" => nil,
               "fundsRaisedBtcIcoEndPrice" => nil,
               "icos" => []
             }
  end

  # Private functions

  defp get_authorization_header do
    username = context_config(:basic_auth_username)
    password = context_config(:basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end

  defp context_config(key) do
    Application.get_env(:sanbase, SanbaseWeb.Graphql.ContextPlug)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
