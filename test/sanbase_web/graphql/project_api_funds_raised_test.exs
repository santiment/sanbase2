defmodule SanbaseWeb.Graphql.ProjectApiFundsRaisedTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Utils.Config, only: [parse_config_value: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.Ico
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    # Add the Projects to the Postgres
    %Project{}
    |> Project.changeset(%{name: "Test project", coinmarketcap_id: "test", ticker: "TEST"})
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{name: "Bitcoin", coinmarketcap_id: "bitcoin", ticker: "BTC"})
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{name: "Ethereum", coinmarketcap_id: "ethereum", ticker: "ETH"})
    |> Repo.insert!()

    # Initialize the Influxdb state
    test_ticker_cmc_id = "TEST_test"
    btc_ticker_cmc_id = "BTC_bitcoin"
    eth_ticker_cmc_id = "ETH_ethereum"

    Store.drop_measurement(test_ticker_cmc_id)
    Store.drop_measurement(btc_ticker_cmc_id)
    Store.drop_measurement(eth_ticker_cmc_id)

    date1 = "2017-08-19"
    date1_unix = 1_503_100_800_000_000_000

    date2 = "2017-10-17"
    date2_unix = 1_508_198_400_000_000_000

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
    currency_eth =
      %Currency{}
      |> Currency.changeset(%{code: "ETH"})
      |> Repo.insert!()

    currency_btc =
      %Currency{}
      |> Currency.changeset(%{code: "BTC"})
      |> Repo.insert!()

    currency =
      %Currency{}
      |> Currency.changeset(%{code: "TEST"})
      |> Repo.insert!()

    # Add a random project and its ICOs
    project =
      %Project{}
      |> Project.changeset(%{name: "Project", coinmarketcap_id: "projjject", ticker: "PROJ"})
      |> Repo.insert!()

    ico1 =
      %Ico{}
      |> Ico.changeset(%{project_id: project.id, end_date: date1})
      |> Repo.insert!()

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico1.id, currency_id: currency_eth.id, amount: 150})
    |> Repo.insert!()

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico1.id, currency_id: currency.id, amount: 50})
    |> Repo.insert!()

    ico2 =
      %Ico{}
      |> Ico.changeset(%{project_id: project.id, end_date: date2})
      |> Repo.insert!()

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico2.id, currency_id: currency_btc.id, amount: 200})
    |> Repo.insert!()

    project_no_ico =
      %Project{}
      |> Project.changeset(%{name: "NoIco", coinmarketcap_id: "no_ico", ticker: "NO_ICO"})
      |> Repo.insert!()

    [
      project: project,
      project_no_ico: project_no_ico
    ]
  end

  test "fetch project public funds raised", context do
    project_id = context.project.id

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
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project_id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => "Project",
               "fundsRaisedUsdIcoEndPrice" => 1200.0,
               "fundsRaisedEthIcoEndPrice" => 250.0,
               "fundsRaisedBtcIcoEndPrice" => 300.0
             }
  end

  test "fetch project funds raised", context do
    project_id = context.project.id

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
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project_id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => "Project",
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
    project_id = context.project_no_ico.id

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
        query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project_id}}")
      )

    assert json_response(result, 200)["data"]["project"] ==
             %{
               "name" => context.project_no_ico.name,
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
