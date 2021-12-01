defmodule SanbaseWeb.Graphql.ProjectApiIsTrendingTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers, only: [execute_query: 3]

  test "fetch social_volume_query project field", context do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project)
    p4 = insert(:random_project, %{slug: "eos"})
    p5 = insert(:random_project, %{slug: "bitcoin"})

    with_mock Sanbase.SocialData.TrendingWords, [],
      get_currently_trending_projects: fn _ -> {:ok, trending_projects()} end do
      result =
        context.conn
        |> execute_query(all_projects_trending_query(), "allProjects")
        |> Enum.sort_by(& &1["slug"])

      expected_result =
        [
          %{"isTrending" => false, "slug" => p1.slug},
          %{"isTrending" => false, "slug" => p2.slug},
          %{"isTrending" => false, "slug" => p3.slug},
          %{"isTrending" => true, "slug" => p4.slug},
          %{"isTrending" => true, "slug" => p5.slug}
        ]
        |> Enum.sort_by(& &1["slug"])

      assert result == expected_result
    end
  end

  defp all_projects_trending_query() do
    """
    {
      allProjects{
        slug
        isTrending
      }
    }
    """
  end

  defp trending_projects() do
    [
      %{score: 372, slug: "eos"},
      %{score: 309, slug: "satoshi"},
      %{score: 228, slug: "time"},
      %{score: 227, slug: "carl"},
      %{score: 196, slug: "donuts"},
      %{score: 190, slug: "like"},
      %{score: 178, slug: "bitcoin"},
      %{score: 172, slug: "mods"},
      %{score: 157, slug: "mod"},
      %{score: 118, slug: "pepper"}
    ]
  end
end
