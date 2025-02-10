defmodule SanbaseWeb.Graphql.ProjectApiDevActivityTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.Github
  alias Sanbase.Project

  setup do
    project1 = insert(:random_project, %{github_organizations: [build(:github_organization)]})

    project2 =
      insert(:random_project, %{
        github_organizations: [build(:github_organization), build(:github_organization)]
      })

    project3 =
      insert(:random_project, %{
        github_organizations: []
      })

    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-02 00:00:00Z]
    dt3 = ~U[2019-01-03 00:00:00Z]

    [project1: project1, project2: project2, project3: project3, dt1: dt1, dt2: dt2, dt3: dt3]
  end

  test "average dev activity for project with 1 organization", %{project1: project} = context do
    {:ok, [org]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, %{org => 300}}
      end do
      result = avg_dev_activity(context.conn, project.slug)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => 10.0}}}
      assert result == expected
    end
  end

  test "average dev activity for project with multple organizations",
       %{project2: project} = context do
    {:ok, [org1, org2]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, %{org1 => 300, org2 => 600}}
      end do
      result = avg_dev_activity(context.conn, project.slug)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => 30.0}}}
      assert result == expected
    end
  end

  test "average dev activity for project with no organizations",
       %{project3: project} = context do
    {:ok, []} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, []}
      end do
      result = avg_dev_activity(context.conn, project.slug)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => nil}}}
      assert result == expected
    end
  end

  test "average dev activity for project with organizations but no data",
       %{project2: project} = context do
    {:ok, [_, _]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, %{}}
      end do
      result = avg_dev_activity(context.conn, project.slug)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => 0}}}
      assert result == expected
    end
  end

  def avg_dev_activity(conn, slug) do
    query = """
    {
      projectBySlug(slug: "#{slug}") {
        averageDevActivity(days: 30)
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end
end
