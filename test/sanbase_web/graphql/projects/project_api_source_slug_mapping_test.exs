defmodule SanbaseWeb.Graphql.ProjectApiSourceSlugMappingTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    project1 = insert(:random_project)
    project2 = insert(:random_project)
    project3 = insert(:random_project, %{source_slug_mappings: []})

    %{project1: project1, project2: project2, project3: project3}
  end

  test "get source slug mappings", context do
    %{conn: conn, project1: p1, project2: p2, project3: p3} = context

    %{
      "data" => %{
        "allProjects" => result
      }
    } = source_slug_mapping(conn)

    result = Enum.sort_by(result, & &1["slug"])

    expected_result =
      Enum.map([p1, p2, p3], fn project ->
        %{
          "slug" => project.slug,
          "sourceSlugMappings" =>
            Enum.map(project.source_slug_mappings, fn ssm ->
              %{
                "source" => ssm.source,
                "slug" => ssm.slug
              }
            end)
        }
      end)
      |> Enum.sort_by(& &1["slug"])

    assert result == expected_result
  end

  defp source_slug_mapping(conn) do
    query = """
    {
      allProjects{
        slug
        sourceSlugMappings {
          slug
          source
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end
end
