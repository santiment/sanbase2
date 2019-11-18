defmodule Sanbase.Model.ProjectListTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Model.Project

  import Sanbase.Factory

  describe "no projects" do
    test "all projects" do
      assert Project.List.projects() == []
    end

    test "all erc20 projects" do
      assert Project.List.erc20_projects() == []
    end

    test "all currency projects" do
      assert Project.List.currency_projects() == []
    end

    test "projects with min_volume above 1000" do
      assert Project.List.projects(min_volume: 1000) == []
    end

    test "without hidden projects" do
      assert Project.List.projects(show_hidden_projects?: false) == []
    end

    test "with hidden projects" do
      assert Project.List.projects(show_hidden_projects?: true) == []
    end

    test "all projects page" do
      assert Project.List.projects_page(1, 10) == []
    end

    test "all erc20 projects page" do
      assert Project.List.erc20_projects_page(1, 10) == []
    end

    test "all currency projects page" do
      assert Project.List.currency_projects_page(1, 10) == []
    end

    test "with source" do
      assert Project.List.projects_with_source("coinmarketcap") == []
    end
  end

  describe "with projects" do
    setup do
      p1 =
        insert(:random_erc20_project)
        |> update_latest_coinmarketcap_data(%{rank: 2, volume_usd: 500})

      p2 =
        insert(:random_erc20_project)
        |> update_latest_coinmarketcap_data(%{rank: 3, volume_usd: 1100})

      p3 =
        insert(:random_erc20_project)
        |> update_latest_coinmarketcap_data(%{rank: 4, volume_usd: 2500})

      p4 = insert(:random_project, source_slug_mappings: [])

      p5 =
        insert(:random_project) |> update_latest_coinmarketcap_data(%{rank: 5, volume_usd: 100})

      p6 = insert(:random_project) |> update_latest_coinmarketcap_data(%{rank: 6})

      p7 =
        insert(:random_project, is_hidden: true)
        |> update_latest_coinmarketcap_data(%{rank: 1, volume_usd: 5000})

      p8 =
        insert(:random_erc20_project, is_hidden: true)
        |> update_latest_coinmarketcap_data(%{rank: 11, volume_usd: 5000})

      hidden_projects = [p7: p7, p8: p8]
      erc20_projects = [p1: p1, p2: p2, p3: p3]
      currency_projects = [p4: p4, p5: p5, p6: p6]
      projects = erc20_projects ++ currency_projects ++ hidden_projects

      [
        total_count: length(projects) - length(hidden_projects),
        total_erc20_count: length(erc20_projects),
        total_currency_count: length(currency_projects),
        total_hidden_count: length(hidden_projects)
      ] ++ projects
    end

    test "all projects", context do
      assert Project.List.projects() |> length == context.total_count
    end

    test "all erc20 projects", context do
      assert Project.List.erc20_projects() |> length == context.total_erc20_count
    end

    test "all currency projects", context do
      assert Project.List.currency_projects() |> length == context.total_currency_count
    end

    test "projects with min_volume above 1000", context do
      projects = Project.List.projects(min_volume: 1000)

      assert length(projects) == 2
      assert context.p2.id in Enum.map(projects, & &1.id)
      assert context.p3.id in Enum.map(projects, & &1.id)
    end

    test "without hidden projects", context do
      projects = Project.List.projects(include_hidden_projects?: false)
      assert length(projects) == context.total_count
      assert context.p7.id not in Enum.map(projects, & &1.id)
      assert context.p8.id not in Enum.map(projects, & &1.id)
    end

    test "with hidden projects", context do
      projects = Project.List.projects(include_hidden_projects?: true)

      assert length(projects) == context.total_count + context.total_hidden_count
      assert context.p7.id in Enum.map(projects, & &1.id)
      assert context.p8.id in Enum.map(projects, & &1.id)
    end

    test "all projects page", context do
      projects = Project.List.projects_page(2, 2)
      assert length(projects) == 2
      assert context.p3.id in Enum.map(projects, & &1.id)
      assert context.p5.id in Enum.map(projects, & &1.id)
    end

    test "all erc20 projects page", context do
      projects = Project.List.erc20_projects_page(1, 2)
      assert length(projects) == 2
      assert context.p1.id in Enum.map(projects, & &1.id)
      assert context.p2.id in Enum.map(projects, & &1.id)
    end

    test "all currency projects page", context do
      projects = Project.List.currency_projects_page(1, 2)
      assert length(projects) == 2
      assert context.p5.id in Enum.map(projects, & &1.id)
      assert context.p6.id in Enum.map(projects, & &1.id)
    end

    test "with source", context do
      projects = Project.List.projects_with_source("coinmarketcap")

      assert length(projects) == 5
      assert context.p4.id not in Enum.map(projects, & &1.id)
    end
  end

  defp update_latest_coinmarketcap_data(project, args) do
    %Sanbase.Model.LatestCoinmarketcapData{}
    |> Sanbase.Model.LatestCoinmarketcapData.changeset(
      %{
        coinmarketcap_id: project.slug,
        update_time: Timex.now()
      }
      |> Map.merge(args)
    )
    |> Sanbase.Repo.insert_or_update()

    Sanbase.Repo.get!(Sanbase.Model.Project, project.id)
  end
end
