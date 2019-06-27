defmodule Sanbase.Graphql.ProjectApiGithubTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.Github

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

    dt1 = "2019-01-01T00:00:00Z" |> from_iso8601!()
    dt2 = "2019-01-02T00:00:00Z" |> from_iso8601!()
    dt3 = "2019-01-03T00:00:00Z" |> from_iso8601!()

    [project1: project1, project2: project2, project3: project3, dt1: dt1, dt2: dt2, dt3: dt3]
  end

  test "average dev activity for project with 1 organization", %{project1: project} = context do
    {:ok, [org]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, [{org, 300}]}
      end do
      result = avg_dev_activity(context.conn, project.coinmarketcap_id)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => 10.0}}}
      assert result == expected
    end
  end

  test "average dev activity for project with multple organizations",
       %{project2: project} = context do
    {:ok, [org1, org2]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, [{org1, 300}, {org2, 600}]}
      end do
      result = avg_dev_activity(context.conn, project.coinmarketcap_id)

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
      result = avg_dev_activity(context.conn, project.coinmarketcap_id)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => nil}}}
      assert result == expected
    end
  end

  test "average dev activity for project with organizations but no data",
       %{project2: project} = context do
    {:ok, [_, _]} = Project.github_organizations(project)

    with_mock Github,
      total_dev_activity: fn _, _, _ ->
        {:ok, []}
      end do
      result = avg_dev_activity(context.conn, project.coinmarketcap_id)

      expected = %{"data" => %{"projectBySlug" => %{"averageDevActivity" => 0}}}
      assert result == expected
    end
  end

  test "dev activity for project with 1 organization", %{project1: project} = context do
    {:ok, [_]} = Project.github_organizations(project)

    with_mock Github,
      dev_activity: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: context.dt1, activity: 100},
           %{datetime: context.dt2, activity: 200},
           %{datetime: context.dt3, activity: 300}
         ]}
      end do
      result =
        dev_activity(context.conn, project.coinmarketcap_id, context.dt1, context.dt2, "1d")

      expected = %{
        "data" => %{
          "devActivity" => [
            %{"activity" => 100, "datetime" => DateTime.to_iso8601(context.dt1)},
            %{"activity" => 200, "datetime" => DateTime.to_iso8601(context.dt2)},
            %{"activity" => 300, "datetime" => DateTime.to_iso8601(context.dt3)}
          ]
        }
      }

      assert result == expected
    end
  end

  test "dev activity for project with multiple organizations", %{project2: project} = context do
    {:ok, [_, _]} = Project.github_organizations(project)

    with_mock Github,
      dev_activity: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: context.dt1, activity: 100},
           %{datetime: context.dt2, activity: 200},
           %{datetime: context.dt3, activity: 300}
         ]}
      end do
      result =
        dev_activity(context.conn, project.coinmarketcap_id, context.dt1, context.dt2, "1d")

      expected = %{
        "data" => %{
          "devActivity" => [
            %{"activity" => 100, "datetime" => DateTime.to_iso8601(context.dt1)},
            %{"activity" => 200, "datetime" => DateTime.to_iso8601(context.dt2)},
            %{"activity" => 300, "datetime" => DateTime.to_iso8601(context.dt3)}
          ]
        }
      }

      assert result == expected
    end
  end

  test "dev activity for project with 0 organizations", %{project3: project} = context do
    {:ok, []} = Project.github_organizations(project)

    with_mock Github,
      dev_activity: fn _, _, _, _, _, _ ->
        {:ok, []}
      end do
      result =
        dev_activity(context.conn, project.coinmarketcap_id, context.dt1, context.dt2, "1d")

      expected = %{
        "data" => %{
          "devActivity" => []
        }
      }

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

  def dev_activity(conn, slug, from, to, interval) do
    query = """
    {
      devActivity(
        slug: "#{slug}",
        from: "#{from}",
        to: "#{to}",
        interval: "#{interval}") {
          datetime
          activity
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end
end
