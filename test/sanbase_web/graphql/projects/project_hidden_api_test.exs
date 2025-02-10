defmodule SanbaseWeb.Graphql.ProjectHiddenApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "all projects", %{conn: conn} do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project, is_hidden: true)

    # Without includeHidden flag.
    projects = all_projects(conn)
    assert length(projects) == 2

    slugs = Enum.map(projects, & &1["slug"])

    assert p1.slug in slugs
    assert p2.slug in slugs
    refute p3.slug in slugs

    # With includeHidden: true flag
    projects = all_projects_including_hidden(conn)
    assert length(projects) == 3

    slugs = Enum.map(projects, & &1["slug"])
    assert p1.slug in slugs
    assert p2.slug in slugs
    assert p3.slug in slugs
  end

  test "project by slug", %{conn: conn} do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    assert {:ok, _} =
             p2
             |> Sanbase.Project.changeset(%{is_hidden: true, hidden_reason: "duplicate"})
             |> Sanbase.Repo.update()

    # not a hidden project
    project = project_by_slug(conn, %{slug: p1.slug})

    assert project == %{
             "hiddenReason" => nil,
             "hiddenSince" => nil,
             "isHidden" => false,
             "slug" => p1.slug
           }

    # hidden project
    project = project_by_slug(conn, %{slug: p2.slug})

    assert %{
             "hiddenReason" => "duplicate",
             "hiddenSince" => dt,
             "isHidden" => true,
             "slug" => slug
           } = project

    assert slug == p2.slug

    assert Sanbase.TestUtils.datetime_close_to(
             DateTime.utc_now(),
             Sanbase.DateTimeUtils.from_iso8601!(dt),
             1,
             :seconds
           )
  end

  defp project_by_slug(conn, args) do
    query = """
    {
      projectBySlug(#{map_to_args(args)}){
        slug
        isHidden
        hiddenSince
        hiddenReason
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "projectBySlug"])
  end

  defp all_projects(conn) do
    query = """
    {
      allProjects{
        slug
        isHidden
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "allProjects"])
  end

  defp all_projects_including_hidden(conn) do
    query = """
    {
      allProjects(includeHidden: true){
        slug
        isHidden
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "allProjects"])
  end
end
