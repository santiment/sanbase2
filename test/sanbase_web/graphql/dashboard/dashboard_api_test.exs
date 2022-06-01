defmodule SanbaseWeb.Graphql.DashboardApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  describe "create/update/delete dashboard" do
    test "create" do
    end
  end

  describe "work with panels" do
  end

  defp create_dashboard(conn, args) do
    mutation = """
    mutation{
      createDashboard(#{map_to_args(args)}){
        id
        name
        user{ id }
        panels { id }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
  end
end
