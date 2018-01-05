defmodule SanbaseWeb.Graphql.ProjectApiFundsRaisedTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Sanbase.Utils, only: [parse_config_value: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Ico
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    Store.drop_measurement("TEST_USD")
    Store.drop_measurement("TEST_BTC")
    Store.drop_measurement("BTC_USD")
    Store.drop_measurement("ETH_USD")

    date1 = "2017-08-19"
    date1_unix = 1503100800000000000

    date2 = "2017-10-17"
    date2_unix = 1508198400000000000

    now = Ecto.DateTime.utc()

    Store.import([
      %Measurement{
        timestamp: date1_unix,
        fields: %{price: 2, volume: 200, marketcap: 500},
        name: "BTC_USD"
      },
      %Measurement{
        timestamp: date1_unix,
        fields: %{price: 4, volume: 200, marketcap: 500},
        name: "TEST_USD"
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price: 5, volume: 200, marketcap: 500},
        name: "BTC_USD"
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price: 10, volume: 200, marketcap: 500},
        name: "ETH_USD"
      }
    ])

    currency = %Currency{}
    |> Currency.changeset(%{code: "TEST"})
    |> Repo.insert!

    project = %Project{}
    |> Project.changeset(%{name: "Project"})
    |> Repo.insert!()

    ico1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project.id,
        end_date: date1,
        funds_raised_eth: 150
        })
    |> Repo.insert!()

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico1.id, currency_id: currency.id, amount: 50})
    |> Repo.insert!

    %Ico{}
    |> Ico.changeset(
      %{project_id: project.id,
        end_date: date2,
        funds_raised_btc: 200
        })
    |> Repo.insert!()

    :ok
  end

  test "fetch project funds raised", context do
    query = """
    {
      allProjects {
        name,
        fundsRaisedUsdIcoPrice,
        fundsRaisedEthIcoPrice,
        fundsRaisedBtcIcoPrice,
        icos {
          endDate,
          fundsRaisedUsdIcoPrice,
          fundsRaisedEthIcoPrice,
          fundsRaisedBtcIcoPrice
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "allProjects"))

    assert json_response(result, 200)["data"]["allProjects"] ==
      [%{"name" => "Project",
        "fundsRaisedUsdIcoPrice" => "1200",
        "fundsRaisedEthIcoPrice" => "250.0",
        "fundsRaisedBtcIcoPrice" => "300",
        "icos" => [
          %{"endDate" => "2017-08-19",
          "fundsRaisedUsdIcoPrice" => "200",
          "fundsRaisedEthIcoPrice" => "150",
          "fundsRaisedBtcIcoPrice" => "100"},
          %{"endDate" => "2017-10-17",
            "fundsRaisedUsdIcoPrice" => "1000",
            "fundsRaisedEthIcoPrice" => "100.0",
            "fundsRaisedBtcIcoPrice" => "200"}]}]
  end

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
