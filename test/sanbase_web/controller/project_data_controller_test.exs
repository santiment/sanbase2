defmodule SanbaseWeb.ProjectDataControllerTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.Project

  import Sanbase.Factory

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project)

    %{p1: p1, p2: p2, p3: p3}
  end

  test "fetch data", context do
    result =
      context.conn
      |> get("/projects_data")
      |> response(200)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert project_data(context.p1) in result
    assert project_data(context.p2) in result
    assert project_data(context.p3) in result
  end

  defp project_data(project) do
    {:ok, contract, decimals} = Project.contract_info(project)
    {:ok, infrastructure} = Project.infrastructure(project)
    {:ok, github_organizations} = Project.github_organizations(project)

    %{
      "contract" => contract,
      "decimals" => decimals,
      "ticker" => project.ticker,
      "slug" => project.slug,
      "infrastructure" => infrastructure.code,
      "github_organizations" => github_organizations
    }
  end
end
