defmodule Sanbase.Graphql.ProjectApiGetQueriesTest do
  use SanbaseWeb.ConnCase

  require Sanbase.Utils.Config

  alias Sanbase.Model.{
    Project,
    Infrastructure,
    Ico
  }

  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    infr_eth =
      %Infrastructure{}
      |> Infrastructure.changeset(%{code: "ETH"})
      |> Repo.insert!()

    infr_btc =
      %Infrastructure{}
      |> Infrastructure.changeset(%{code: "BTC"})
      |> Repo.insert!()

    project1 =
      %Project{}
      |> Project.changeset(%{
        name: "Project1",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj1"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project1.id, main_contract_address: "0x123123"})
    |> Repo.insert!()

    project2 =
      %Project{}
      |> Project.changeset(%{
        name: "Project2",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj2"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project2.id})
    |> Repo.insert!()

    project3 =
      %Project{}
      |> Project.changeset(%{
        name: "Project3",
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: "proj3"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project3.id})
    |> Repo.insert!()

    :ok
  end

  test "fetch all projects", context do
    query = """
    {
      allProjects{
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjects"))

    projects = json_response(result, 200)["data"]["allProjects"]

    assert %{"name" => "Project1"} in projects
    assert %{"name" => "Project2"} in projects
    assert %{"name" => "Project3"} in projects
  end

  test "fetch all erc20 projects", context do
    query = """
    {
      allErc20Projects {
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allErc20Projects"))

    projects = json_response(result, 200)["data"]["allErc20Projects"]

    assert %{"name" => "Project1"} in projects
    assert %{"name" => "Project2"} not in projects
    assert %{"name" => "Project3"} not in projects
  end

  test "fetch all currency projects", context do
    query = """
    {
      allCurrencyProjects {
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))

    projects = json_response(result, 200)["data"]["allCurrencyProjects"]

    assert %{"name" => "Project1"} not in projects
    assert %{"name" => "Project2"} in projects
    assert %{"name" => "Project3"} in projects
  end
end
