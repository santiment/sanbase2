defmodule Sanbase.ProjectMultichainTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  setup do
    _ = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)
    _ = insert(:random_erc20_project)

    arbitrum_tether =
      insert(:project, slug: "arb-tether", ticker: "USDT", name: "Tether [on Arbitrum]")

    optimism_tether =
      insert(:project, slug: "o-tether", ticker: "USDT", name: "Tether [on Optimism]")

    arbitrum_ecosystem = insert(:ecosystem, ecosystem: "arbitrum")
    optimism_ecosystem = insert(:ecosystem, ecosystem: "optimism")

    {:ok,
     %{
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
end
