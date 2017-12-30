defmodule SanbaseWeb.Graphql.ProjectApiRoiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Sanbase.Utils, only: [parse_config_value: 1]

  alias Sanbase.Model.Project
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

    date1 = "2017-08-19"
    date1_unix = 1503100800000000000

    date2 = "2017-10-17"
    date2_unix = 1508198400000000000

    now = Ecto.DateTime.utc()

    Store.import([
      %Measurement{
        timestamp: date1_unix,
        fields: %{price: 5, volume: 200, marketcap: 500},
        name: "TEST_USD"
      },
      %Measurement{
        timestamp: date2_unix,
        fields: %{price: 20, volume: 200, marketcap: 500},
        name: "TEST_USD"
      }
    ])

    %LatestCoinmarketcapData{}
    |> LatestCoinmarketcapData.changeset(%{coinmarketcap_id: "TEST_ID", price_usd: 50, update_time: now})
    |> Repo.insert!

    project = %Project{}
    |> Project.changeset(%{name: "Project", ticker: "TEST", coinmarketcap_id: "TEST_ID"})
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(
      %{project_id: project.id,
        end_date: date1
        })
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(
      %{project_id: project.id,
        end_date: date2
        })
    |> Repo.insert!()

    :ok
  end

  test "fetch project ROI", context do
    query = """
    {
      allProjects {
        name,
        roiUsd
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "allProjects"))

    assert json_response(result, 200)["data"]["allProjects"] ==
      [%{"name" => "Project", "roiUsd" => "4"}]
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
