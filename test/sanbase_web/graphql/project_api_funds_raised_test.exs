defmodule SanbaseWeb.Graphql.ProjectApiFundsRaisedTest do
  use SanbaseWeb.ConnCase

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

  defp setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    Store.drop_measurement("TEST_USD")
    Store.drop_measurement("TEST_BTC")
    Store.drop_measurement("BTC_USD")
    Store.drop_measurement("ETH_USD")

    date1 = DateTime.from_naive!(~N[2017-08-19 00:00:00], "Etc/UTC")
    date1_unix = DateTime.to_unix(date1, :nanoseconds)

    date2 = DateTime.from_naive!(~N[2017-10-17 00:00:00], "Etc/UTC")
    date2_unix = DateTime.to_unix(date2, :nanoseconds)

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

    project =
      %Project{}
      |> Project.changeset(%{name: "Project"})
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

    project.id
  end

  test "fetch project public funds raised", context do
    project_id = setup()

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
               "fundsRaisedUsdIcoEndPrice" => "1200",
               "fundsRaisedEthIcoEndPrice" => "250.0",
               "fundsRaisedBtcIcoEndPrice" => "300"
             }
  end

  test "fetch project funds raised", context do
    project_id = setup()

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
               "fundsRaisedUsdIcoEndPrice" => "1200",
               "fundsRaisedEthIcoEndPrice" => "250.0",
               "fundsRaisedBtcIcoEndPrice" => "300",
               "icos" => [
                 %{
                   "endDate" => "2017-08-19",
                   "fundsRaisedUsdIcoEndPrice" => "200",
                   "fundsRaisedEthIcoEndPrice" => "150",
                   "fundsRaisedBtcIcoEndPrice" => "100"
                 },
                 %{
                   "endDate" => "2017-10-17",
                   "fundsRaisedUsdIcoEndPrice" => "1000",
                   "fundsRaisedEthIcoEndPrice" => "100.0",
                   "fundsRaisedBtcIcoEndPrice" => "200"
                 }
               ]
             }
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
