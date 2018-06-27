defmodule SanbaseWeb.Graphql.ProjectApiRoiTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Utils.Config

  alias Sanbase.Model.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Ico
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Utils.Config

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  defp setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    date1 = "2017-08-19"
    date1_unix = 1_503_100_800_000_000_000

    date2 = "2017-10-17"
    date2_unix = 1_508_198_400_000_000_000

    now = Ecto.DateTime.utc()

    Store.import([
      %Measurement{
        timestamp: date1_unix,
        fields: %{price: 5, volume: 200, marketcap: 500},
        name: "ETH_USD"
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price: 5, volume: 200, marketcap: 500},
        name: "ETH_USD"
      }
    ])

    %LatestCoinmarketcapData{}
    |> LatestCoinmarketcapData.changeset(%{
      coinmarketcap_id: "TEST_ID",
      price_usd: 50,
      available_supply: 500,
      update_time: now
    })
    |> Repo.insert!()

    project =
      %Project{}
      |> Project.changeset(%{name: "Project", ticker: "TEST", coinmarketcap_id: "TEST_ID"})
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project.id, token_usd_ico_price: 10, tokens_sold_at_ico: 100})
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project.id, start_date: date1})
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project.id, start_date: date2, token_eth_ico_price: 5})
    |> Repo.insert!()

    project.id
  end

  test "fetch project ROI", context do
    project_id = setup()

    query = """
    {
      project(id: $id) {
        name,
        roiUsd
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
             %{"name" => "Project", "roiUsd" => "2.5"}
  end

  defp get_authorization_header do
    username = context_config(:basic_auth_username)
    password = context_config(:basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end

  defp context_config(key) do
    Config.module_get(SanbaseWeb.Graphql.ContextPlug, key)
  end
end
