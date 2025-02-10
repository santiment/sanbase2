defmodule SanbaseWeb.Graphql.ProjectApiGithubTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.Github
  alias Sanbase.Project

  setup do
    market_segment_without_projects = insert(:market_segment)
    market_segment = insert(:market_segment)

    project1 =
      insert(:random_project, %{
        github_organizations: [build(:github_organization)],
        market_segments: [market_segment]
      })

    project2 =
      insert(:random_project, %{
        github_organizations: [build(:github_organization), build(:github_organization)],
        market_segments: [market_segment]
      })

    project3 = insert(:random_project, %{github_organizations: [], market_segments: []})

    %{
      project1: project1,
      project2: project2,
      project3: project3,
      dt1: ~U[2019-01-01T00:00:00Z],
      dt2: ~U[2019-01-02T00:00:00Z],
      dt3: ~U[2019-01-03T00:00:00Z],
      market_segment: market_segment,
      market_segment_without_projects: market_segment_without_projects
    }
  end

  describe "dev activity for slug" do
    test "with 1 organization", %{project1: project} = context do
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
        result = dev_activity_by_slug(context.conn, project.slug, context.dt1, context.dt3, "1d")

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

    test "with multiple organizations", %{project2: project} = context do
      {:ok, [_, _ | _]} = Project.github_organizations(project)

      with_mock Github,
        dev_activity: fn _, _, _, _, _, _ ->
          {:ok,
           [
             %{datetime: context.dt1, activity: 100},
             %{datetime: context.dt2, activity: 200},
             %{datetime: context.dt3, activity: 300}
           ]}
        end do
        result = dev_activity_by_slug(context.conn, project.slug, context.dt1, context.dt3, "1d")

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

    test "with 0 organizations", %{project3: project} = context do
      {:ok, []} = Project.github_organizations(project)

      with_mock Github,
        dev_activity: fn _, _, _, _, _, _ ->
          {:ok, []}
        end do
        result = dev_activity_by_slug(context.conn, project.slug, context.dt1, context.dt3, "1d")

        expected = %{
          "data" => %{
            "devActivity" => []
          }
        }

        assert result == expected
      end
    end
  end

  describe "dev activity for market segments" do
    test "one segment with multiple projects", context do
      (&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6)
      |> Sanbase.Mock.prepare_mock2(
        {:ok,
         [
           %{datetime: context.dt1, value: 100},
           %{datetime: context.dt2, value: 200},
           %{datetime: context.dt3, value: 300}
         ]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          dev_activity_by_market_segment_all_of(
            context.conn,
            [context.market_segment.name],
            context.dt1,
            context.dt3,
            "1d"
          )

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
      end)
    end

    test "multiple segments that no project has", context do
      (&Sanbase.Clickhouse.Github.MetricAdapter.timeseries_data/6)
      |> Sanbase.Mock.prepare_mock2({:ok, []})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          dev_activity_by_market_segment_all_of(
            context.conn,
            [context.market_segment.name, context.market_segment_without_projects.name],
            context.dt1,
            context.dt3,
            "1d"
          )

        expected = %{
          "data" => %{
            "devActivity" => []
          }
        }

        assert result == expected
      end)
    end
  end

  def dev_activity_by_slug(conn, slug, from, to, interval) do
    query = """
    {
      devActivity(
        selector: {slug: "#{slug}"},
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

  def dev_activity_by_market_segment_all_of(conn, market_segments, from, to, interval) do
    query = """
    {
      devActivity(
        selector: {marketSegments: #{inspect(market_segments)}},
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
