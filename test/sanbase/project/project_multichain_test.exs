defmodule Sanbase.ProjectMultichainTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    p = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    arbitrum_tether =
      insert(:project, slug: "arb-tether", ticker: "USDT", name: "Tether [on Arbitrum]")

    optimism_tether =
      insert(:project, slug: "o-tether", ticker: "USDT", name: "Tether [on Optimism]")

    arbitrum_ecosystem = insert(:ecosystem, ecosystem: "arbitrum")
    optimism_ecosystem = insert(:ecosystem, ecosystem: "optimism")

    {:ok,
     %{
       conn: conn,
       project: p,
       user: user,
       arbitrum_tether: arbitrum_tether,
       optimism_tether: optimism_tether,
       arbitrum_ecosystem: arbitrum_ecosystem,
       optimism_ecosystem: optimism_ecosystem
     }}
  end

  test "mark as multichain", context do
    {:ok, _} =
      Sanbase.Project.Multichain.mark_multichain(
        context.arbitrum_tether,
        multichain_project_group_key: "tether",
        ecosystem_id: context.arbitrum_ecosystem.id
      )

    {:ok, _} =
      Sanbase.Project.Multichain.mark_multichain(
        context.optimism_tether,
        multichain_project_group_key: "tether",
        ecosystem_id: context.optimism_ecosystem.id
      )

    projects = Sanbase.Project.List.projects()

    groups =
      Enum.group_by(projects, & &1.multichain_project_group_key, & &1.slug)
      |> Map.new(fn {k, v} -> {k, Enum.sort(v)} end)

    assert %{
             "tether" => ["arb-tether", "o-tether"],
             nil => [_ | _]
           } = groups
  end

  test "combined marketcap", context do
    watchlist = insert(:watchlist, user: context.user, name: "multichain")

    {:ok, watchlist} =
      Sanbase.UserList.update_user_list(context.user, %{
        id: watchlist.id,
        list_items: [
          %{project_id: context.project.id},
          %{project_id: context.arbitrum_tether.id},
          %{project_id: context.optimism_tether.id}
        ]
      })

    Sanbase.Mock.prepare_mock(Sanbase.Price, :combined_marketcap_and_volume, fn slugs, _, _, _ ->
      assert length(slugs) == 3
      assert context.project.slug in slugs
      assert "arb-tether" in slugs
      assert "o-tether" in slugs
      {:ok, []}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        watchlist(id: #{watchlist.id}){
          id
          historicalStats(from: "utc_now-7d", to: "utc_now", interval: "1d") {
            datetime
            marketcap
            volume
          }
        }
      }
      """

      data =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert %{"data" => %{"watchlist" => %{"historicalStats" => [], "id" => "#{watchlist.id}"}}} ==
               data
    end)

    # Now mark the projects as multichain and expect that only one of them appears in the query

    {:ok, _} =
      Sanbase.Project.Multichain.mark_multichain(
        context.arbitrum_tether,
        multichain_project_group_key: "tether",
        ecosystem_id: context.arbitrum_ecosystem.id
      )

    {:ok, _} =
      Sanbase.Project.Multichain.mark_multichain(
        context.optimism_tether,
        multichain_project_group_key: "tether",
        ecosystem_id: context.optimism_ecosystem.id
      )

    Sanbase.Mock.prepare_mock(Sanbase.Price, :combined_marketcap_and_volume, fn slugs, _, _, _ ->
      assert length(slugs) == 2
      assert context.project.slug in slugs
      assert "arb-tether" in slugs or "o-tether" in slugs
      {:ok, []}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        watchlist(id: #{watchlist.id}){
          id
          historicalStats(from: "utc_now-7d", to: "utc_now", interval: "1d") {
            datetime
            marketcap
            volume
          }
        }
      }
      """

      data =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert %{"data" => %{"watchlist" => %{"historicalStats" => [], "id" => "#{watchlist.id}"}}} ==
               data
    end)
  end
end
