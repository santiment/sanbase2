defmodule Sanbase.Project.EcosystemTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  describe "string ecosystem and full ecosystem path - OLD" do
    test "compute full path ecosystem" do
      insert(:project, name: "Ethereum", slug: "ethereum", ecosystem: "ethereum")
      insert(:project, name: "Bitcoin", slug: "bitcoin", ecosystem: "bitcoin")
      insert(:project, name: "Santiment", slug: "santiment", ecosystem: "ethereum")
      insert(:project, name: "Arbitrum", slug: "arbitrum", ecosystem: "ethereum")
      insert(:project, name: "Xyz", slug: "xyz", ecosystem: "arbitrum")
      insert(:project, name: "Abc", slug: "abc", ecosystem: "arbitrum")
      insert(:project, name: "Ykc", slug: "ykc", ecosystem: "abc")

      list =
        Enum.map(Sanbase.Project.Job.compute_ecosystem_full_path(), fn {p, e} -> {p.slug, e} end)

      expected_list = [
        {"abc", "/ethereum/arbitrum/abc/"},
        {"arbitrum", "/ethereum/arbitrum/"},
        {"bitcoin", "/bitcoin/"},
        {"ethereum", "/ethereum/"},
        {"santiment", "/ethereum/santiment/"},
        {"xyz", "/ethereum/arbitrum/xyz/"},
        {"ykc", "/ethereum/arbitrum/abc/ykc/"}
      ]

      assert Enum.sort(list) == Enum.sort(expected_list)
    end
  end

  describe "multiple ecosystems per project" do
    test "add ecosystem" do
      assert {:ok, _} = Sanbase.Ecosystem.create_ecosystem("ethereum")
      assert {:ok, _} = Sanbase.Ecosystem.create_ecosystem("bitcoin")
      assert {:error, _} = Sanbase.Ecosystem.create_ecosystem("ethereum")

      assert {:ok, ecosystems} = Sanbase.Ecosystem.get_ecosystems()

      assert Enum.sort(ecosystems) == ["bitcoin", "ethereum"]
    end

    test "add ecosystem to a project" do
      project = insert(:random_erc20_project)

      assert {:ok, ecosystem_eth} = Sanbase.Ecosystem.create_ecosystem("ethereum")
      assert {:ok, ecosystem_arb} = Sanbase.Ecosystem.create_ecosystem("arbitrum")
      assert {:ok, _} = Sanbase.Ecosystem.create_ecosystem("bitcoin")

      assert {:ok, _} = Sanbase.Ecosystem.add_ecosystem_to_project(project.id, ecosystem_eth.id)
      assert {:ok, _} = Sanbase.Ecosystem.add_ecosystem_to_project(project.id, ecosystem_arb.id)

      assert {:ok, ecosystems} = Sanbase.Ecosystem.get_project_ecosystems(project.id)

      assert Enum.sort(ecosystems) == ["arbitrum", "ethereum"]
    end

    test "get all projects in an ecosystem" do
      project = insert(:random_erc20_project)
      project2 = insert(:random_erc20_project)
      project3 = insert(:random_erc20_project)

      assert {:ok, ecosystem_eth} = Sanbase.Ecosystem.create_ecosystem("ethereum")
      assert {:ok, ecosystem_arb} = Sanbase.Ecosystem.create_ecosystem("arbitrum")

      assert {:ok, _} = Sanbase.Ecosystem.add_ecosystem_to_project(project.id, ecosystem_eth.id)
      assert {:ok, _} = Sanbase.Ecosystem.add_ecosystem_to_project(project2.id, ecosystem_eth.id)
      assert {:ok, _} = Sanbase.Ecosystem.add_ecosystem_to_project(project3.id, ecosystem_arb.id)

      assert {:ok, projects} = Sanbase.Ecosystem.get_projects_by_ecosystem_names(["ethereum"])
      assert Enum.sort(Enum.map(projects, & &1.id)) == Enum.sort([project.id, project2.id])

      assert {:ok, projects} = Sanbase.Ecosystem.get_projects_by_ecosystem_names(["arbitrum"])
      assert Enum.map(projects, & &1.id) == [project3.id]
    end
  end
end
