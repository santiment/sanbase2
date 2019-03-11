defmodule Sanbase.Graphql.ProjectApiMinVolumeQueriesTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.{
    Project,
    Infrastructure
  }

  alias Sanbase.Repo
  alias Sanbase.Model.LatestCoinmarketcapData
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
        ticker: "PRJ1",
        name: "Project1",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj1",
        main_contract_address: "0x1111111"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{volume_usd: 1000, rank: 10})

    project2 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ2",
        name: "Project2",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj2",
        main_contract_address: "0x2222222"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{volume_usd: 2000, rank: 9})

    project3 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ3",
        name: "Project3",
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: "proj3"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{volume_usd: 3000, rank: 5})

    project4 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ4",
        name: "Project4",
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: "proj4"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{volume_usd: 4000, rank: 3})

    project5 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ5",
        name: "Project5",
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: "proj5",
        main_contract_address: "0x333333333"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{rank: 50})

    project6 =
      %Project{}
      |> Project.changeset(%{
        ticker: "PRJ6",
        name: "Project6",
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: "proj6"
      })
      |> Repo.insert!()
      |> update_latest_coinmarketcap_data(%{rank: 100})

    [
      project1: project1,
      project2: project2,
      project3: project3,
      project4: project4,
      project5: project5,
      project6: project6,
      projects_count: 6,
      projects_with_volume_count: 4,
      erc20_projects_count: 3,
      erc20_projects_with_volume_count: 2,
      currency_projects_count: 3,
      currency_projects_with_volume_count: 2
    ]
  end

  describe "all_projects query" do
    test "no min_volume specified fetches all projects", context do
      query = """
      {
        allProjects{
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == context.projects_count
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allProjects(minVolume: 0){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == context.projects_with_volume_count
    end

    test "min_volume and fetch first page", context do
      query = """
      {
        allProjects(minVolume: 1000, page: 1, pageSize: 2){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == 2
      assert result["data"]["allProjects"] == [%{"name" => "Project4"}, %{"name" => "Project3"}]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allProjects(minVolume: 1000, page: 2, pageSize: 2){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == 2
      assert result["data"]["allProjects"] == [%{"name" => "Project2"}, %{"name" => "Project1"}]
    end
  end

  describe "all_erc20_projects query" do
    test "no min_volume specified fetches all projects", context do
      query = """
      {
        allErc20Projects{
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == context.erc20_projects_count
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allErc20Projects(minVolume: 0){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length ==
               context.erc20_projects_with_volume_count
    end

    test "min_volume and fetch first page", context do
      query = """
      {
        allErc20Projects(minVolume: 1000, page: 1, pageSize: 1){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == 1
      assert result["data"]["allErc20Projects"] == [%{"name" => "Project2"}]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allErc20Projects(minVolume: 1000, page: 2, pageSize: 1){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == 1
      assert result["data"]["allErc20Projects"] == [%{"name" => "Project1"}]
    end
  end

  describe "all_currency_projects query" do
    test "no min_volume specified fetches all projects", context do
      query = """
      {
        allCurrencyProjects{
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == context.currency_projects_count
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allCurrencyProjects(minVolume: 0){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length ==
               context.currency_projects_with_volume_count
    end

    test "min_volume and fetch first page", context do
      query = """
      {
        allCurrencyProjects(minVolume: 1000, page: 1, pageSize: 1){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == 1
      assert result["data"]["allCurrencyProjects"] == [%{"name" => "Project4"}]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allCurrencyProjects(minVolume: 1000, page: 2, pageSize: 1){
          name,
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == 1
      assert result["data"]["allCurrencyProjects"] == [%{"name" => "Project3"}]
    end
  end

  defp update_latest_coinmarketcap_data(project, args) do
    %LatestCoinmarketcapData{}
    |> LatestCoinmarketcapData.changeset(
      %{
        coinmarketcap_id: project.coinmarketcap_id,
        update_time: Timex.now()
      }
      |> Map.merge(args)
    )
    |> Repo.insert_or_update()

    Repo.get!(Project, project.id)
  end
end
