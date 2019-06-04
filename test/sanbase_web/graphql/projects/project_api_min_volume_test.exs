defmodule Sanbase.Graphql.ProjectApiMinVolumeQueriesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Model.Project

  alias Sanbase.Repo
  alias Sanbase.Model.LatestCoinmarketcapData

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})
    infr_btc = insert(:infrastructure, %{code: "BTC"})

    project1 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
      |> update_latest_coinmarketcap_data(%{volume_usd: 1000, rank: 10})

    project2 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
      |> update_latest_coinmarketcap_data(%{volume_usd: 2000, rank: 9})

    project3 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
      |> update_latest_coinmarketcap_data(%{volume_usd: 3000, rank: 5})

    project4 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
      |> update_latest_coinmarketcap_data(%{volume_usd: 4000, rank: 3})

    project5 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_eth.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
      |> update_latest_coinmarketcap_data(%{rank: 50})

    project6 =
      insert(:project, %{
        ticker: rand_str(4),
        name: rand_str(),
        infrastructure_id: infr_btc.id,
        coinmarketcap_id: rand_str(),
        main_contract_address: "0x" <> rand_hex_str()
      })
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
          name
          volumeUsd
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == context.projects_count

      #  Assert that there are projects with known and with unknown volumes
      volumes =
        result["data"]["allProjects"]
        |> Enum.map(& &1["volumeUsd"])

      non_nil_volumes =
        volumes
        |> Enum.reject(&is_nil/1)

      assert length(volumes) > 0
      assert length(non_nil_volumes) > 0
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allProjects(minVolume: 0){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == context.projects_with_volume_count

      assert result["data"]["allProjects"] == [
               %{"name" => context.project4.name},
               %{"name" => context.project3.name},
               %{"name" => context.project2.name},
               %{"name" => context.project1.name}
             ]
    end

    test "min_volume and fetch first page", context do
      query = """
      {
        allProjects(minVolume: 1000, page: 1, pageSize: 2){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == 2

      assert result["data"]["allProjects"] == [
               %{"name" => context.project4.name},
               %{"name" => context.project3.name}
             ]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allProjects(minVolume: 1000, page: 2, pageSize: 2){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allProjects"))
        |> json_response(200)

      assert result["data"]["allProjects"] |> length == 2

      assert result["data"]["allProjects"] == [
               %{"name" => context.project2.name},
               %{"name" => context.project1.name}
             ]
    end
  end

  describe "all_erc20_projects query" do
    test "no min_volume specified fetches all projects", context do
      query = """
      {
        allErc20Projects{
          rank
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == context.erc20_projects_count

      assert result["data"]["allErc20Projects"] |> Enum.sort_by(& &1["rank"]) == [
               %{"rank" => 9, "name" => context.project2.name},
               %{"rank" => 10, "name" => context.project1.name},
               %{"rank" => 50, "name" => context.project5.name}
             ]
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allErc20Projects(minVolume: 0){
          name
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
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == 1
      assert result["data"]["allErc20Projects"] == [%{"name" => context.project2.name}]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allErc20Projects(minVolume: 1000, page: 2, pageSize: 1){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allErc20Projects"))
        |> json_response(200)

      assert result["data"]["allErc20Projects"] |> length == 1
      assert result["data"]["allErc20Projects"] == [%{"name" => context.project1.name}]
    end
  end

  describe "all_currency_projects query" do
    test "no min_volume specified fetches all projects", context do
      query = """
      {
        allCurrencyProjects{
          rank
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == context.currency_projects_count

      assert result["data"]["allCurrencyProjects"] |> Enum.sort_by(& &1["rank"]) == [
               %{"rank" => 3, "name" => context.project4.name},
               %{"rank" => 5, "name" => context.project3.name},
               %{"rank" => 100, "name" => context.project6.name}
             ]
    end

    test "min_volume 0 specified fetches all projects with volume data", context do
      query = """
      {
        allCurrencyProjects(minVolume: 0){
          name
          volumeUsd
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length ==
               context.currency_projects_with_volume_count

      volumes = result["data"]["allCurrencyProjects"] |> Enum.map(& &1["volumeUsd"])
      # no nil volumes are returned
      refute Enum.any?(volumes, &is_nil/1)
    end

    test "min_volume and fetch first page", context do
      query = """
      {
        allCurrencyProjects(minVolume: 1000, page: 1, pageSize: 1){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == 1
      assert result["data"]["allCurrencyProjects"] == [%{"name" => context.project4.name}]
    end

    test "min_volume and fetch second page", context do
      query = """
      {
        allCurrencyProjects(minVolume: 1000, page: 2, pageSize: 1){
          name
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "allCurrencyProjects"))
        |> json_response(200)

      assert result["data"]["allCurrencyProjects"] |> length == 1
      assert result["data"]["allCurrencyProjects"] == [%{"name" => context.project3.name}]
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
