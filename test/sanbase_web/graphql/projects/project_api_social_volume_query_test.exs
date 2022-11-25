defmodule SanbaseWeb.Graphql.ProjectApiSocialVolumeQueryTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Project

  test "default social volume for projects without predefined one", %{conn: conn} do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    result = execute_query(conn, all_projects_social_volume_query(), "allProjects")

    expected_result = [
      %{
        "slug" => p1.slug,
        "socialVolumeQuery" => Project.SocialVolumeQuery.default_query(p1)
      },
      %{
        "slug" => p2.slug,
        "socialVolumeQuery" => Project.SocialVolumeQuery.default_query(p2)
      }
    ]

    assert result |> Enum.sort_by(& &1["slug"]) == expected_result |> Enum.sort_by(& &1["slug"])
  end

  test "social volume for projects with predefined query", %{conn: conn} do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    insert(:social_volume_query, %{project: p1, query: "something"})
    insert(:social_volume_query, %{project: p2, query: "something else"})
    result = execute_query(conn, all_projects_social_volume_query(), "allProjects")

    expected_result = [
      %{
        "slug" => p1.slug,
        "socialVolumeQuery" => "something"
      },
      %{
        "slug" => p2.slug,
        "socialVolumeQuery" => "something else"
      }
    ]

    assert result |> Enum.sort_by(& &1["slug"]) == expected_result |> Enum.sort_by(& &1["slug"])
  end

  defp all_projects_social_volume_query() do
    """
    {
      allProjects{
        slug
        socialVolumeQuery
      }
    }
    """
  end
end
