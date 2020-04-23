defmodule SanbaseWeb.Graphql.ProjectApiFiltersTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Model.Project

  alias Sanbase.Repo
  alias Sanbase.Model.LatestCoinmarketcapData

  setup do
    [
      p1: insert(:random_project),
      p2: insert(:random_project),
      p3: insert(:random_project),
      p4: insert(:random_project),
      p5: insert(:random_project)
    ]
  end

  defp filtered_projects(metric, from, to, aggregation, operator, threshold) do
    query = """
    {
      allProjects
    }
    """
  end
end
