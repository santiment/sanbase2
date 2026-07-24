defmodule SanbaseWeb.Graphql.GithubActivityStatsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    p1 = insert(:random_project, %{github_organizations: [build(:github_organization)]})

    p2 =
      insert(:random_project, %{
        github_organizations: [build(:github_organization), build(:github_organization)]
      })

    p3 = insert(:random_project, %{github_organizations: []})

    %{
      conn: conn,
      p1: p1,
      p2: p2,
      p3: p3,
      from: ~U[2024-04-01 00:00:00Z],
      to: ~U[2024-05-01 00:00:00Z]
    }
  end

  test "get github activity stats for a list of slugs", context do
    rows = [
      [context.p1.slug, 1000, 1500, 20, 30, 100, 200, 3],
      [context.p2.slug, 2000, 3000, 40, 60, 300, 500, 5]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        get_github_activity_stats(
          context.conn,
          %{slugs: [context.p1.slug, context.p2.slug], map_as_input_object: true},
          context.from,
          context.to
        )
        |> get_in(["data", "githubActivityStats"])

      assert data == [
               %{
                 "slug" => context.p1.slug,
                 "devActivity" => 1000,
                 "githubActivity" => 1500,
                 "devActivityContributorsCount" => 20,
                 "githubActivityContributorsCount" => 30,
                 "botDevActivity" => 100,
                 "botGithubActivity" => 200,
                 "botContributorsCount" => 3
               },
               %{
                 "slug" => context.p2.slug,
                 "devActivity" => 2000,
                 "githubActivity" => 3000,
                 "devActivityContributorsCount" => 40,
                 "githubActivityContributorsCount" => 60,
                 "botDevActivity" => 300,
                 "botGithubActivity" => 500,
                 "botContributorsCount" => 5
               }
             ]
    end)
  end

  test "slugs without github organizations or without data get zero values", context do
    rows = [
      [context.p1.slug, 1000, 1500, 20, 30, 100, 200, 3]
    ]

    zero_values = %{
      "devActivity" => 0,
      "githubActivity" => 0,
      "devActivityContributorsCount" => 0,
      "githubActivityContributorsCount" => 0,
      "botDevActivity" => 0,
      "botGithubActivity" => 0,
      "botContributorsCount" => 0
    }

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        get_github_activity_stats(
          context.conn,
          %{
            slugs: [context.p3.slug, context.p1.slug, context.p2.slug],
            map_as_input_object: true
          },
          context.from,
          context.to
        )
        |> get_in(["data", "githubActivityStats"])

      # The result is in the same order as the input slugs. p2 has
      # organizations but no data, p3 has no organizations at all
      assert data == [
               Map.put(zero_values, "slug", context.p3.slug),
               %{
                 "slug" => context.p1.slug,
                 "devActivity" => 1000,
                 "githubActivity" => 1500,
                 "devActivityContributorsCount" => 20,
                 "githubActivityContributorsCount" => 30,
                 "botDevActivity" => 100,
                 "botGithubActivity" => 200,
                 "botContributorsCount" => 3
               },
               Map.put(zero_values, "slug", context.p2.slug)
             ]
    end)
  end

  test "get github activity stats for the top N projects", context do
    hidden_project =
      insert(:random_project, %{
        is_hidden: true,
        github_organizations: [build(:github_organization)]
      })

    # The ranking comes from Sanbase.Metric.slugs_order over the precomputed
    # dev_activity_1d/github_activity_1d metrics. Slugs without a project,
    # with a hidden project or with a project without github organizations (p3)
    # are dropped and do not take up topN spots. Only the top N slugs that can
    # appear in the result are sent to the stats query
    ranked_slugs = [
      "slug-without-a-project",
      hidden_project.slug,
      context.p3.slug,
      context.p2.slug,
      context.p1.slug
    ]

    stats_rows = [
      [context.p2.slug, 2000, 3000, 40, 60, 300, 500, 5],
      [context.p1.slug, 1500, 2500, 20, 30, 100, 200, 3]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.slugs_order/5, {:ok, ranked_slugs})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: stats_rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        get_github_activity_stats(
          context.conn,
          %{top_n: 2, sort_by: :dev_activity, map_as_input_object: true},
          context.from,
          context.to
        )
        |> get_in(["data", "githubActivityStats"])

      assert [
               %{"slug" => slug1, "devActivity" => 2000},
               %{"slug" => slug2, "devActivity" => 1500}
             ] = data

      assert slug1 == context.p2.slug
      assert slug2 == context.p1.slug
    end)
  end

  test "top N digs deeper into the ranking when the top slugs cannot appear in the result",
       context do
    # More slugs without a project than the first overfetched batch
    # (overshoot factor * topN) can absorb. The slugs with github
    # organizations must still fill all topN spots
    ranked_slugs =
      Enum.map(1..11, fn i -> "slug-without-a-project-#{i}" end) ++
        [context.p2.slug, context.p1.slug]

    stats_rows = [
      [context.p2.slug, 2000, 3000, 40, 60, 300, 500, 5],
      [context.p1.slug, 1500, 2500, 20, 30, 100, 200, 3]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.slugs_order/5, {:ok, ranked_slugs})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: stats_rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        get_github_activity_stats(
          context.conn,
          %{top_n: 2, sort_by: :dev_activity, map_as_input_object: true},
          context.from,
          context.to
        )
        |> get_in(["data", "githubActivityStats"])

      assert [
               %{"slug" => slug1, "devActivity" => 2000},
               %{"slug" => slug2, "devActivity" => 1500}
             ] = data

      assert slug1 == context.p2.slug
      assert slug2 == context.p1.slug
    end)
  end

  test "error when the selector has both slugs and topN", context do
    %{"errors" => [error]} =
      get_github_activity_stats(
        context.conn,
        %{slugs: [context.p1.slug], top_n: 10, sort_by: :dev_activity, map_as_input_object: true},
        context.from,
        context.to
      )

    assert error["message"] =~ "exactly one of the fields slugs and topN, not both"
  end

  test "error when the selector has neither slugs nor topN", context do
    %{"errors" => [error]} =
      get_github_activity_stats(
        context.conn,
        %{sort_by: :dev_activity, map_as_input_object: true},
        context.from,
        context.to
      )

    assert error["message"] =~ "exactly one of the fields slugs and topN"
  end

  test "error when topN is used without sortBy", context do
    %{"errors" => [error]} =
      get_github_activity_stats(
        context.conn,
        %{top_n: 10, map_as_input_object: true},
        context.from,
        context.to
      )

    assert error["message"] =~ "must have the sortBy field when topN is used"
  end

  test "error when topN is too big", context do
    %{"errors" => [error]} =
      get_github_activity_stats(
        context.conn,
        %{top_n: 101, sort_by: :github_activity, map_as_input_object: true},
        context.from,
        context.to
      )

    assert error["message"] =~ "topN must be between 1 and 100"
  end

  test "the current day data is included", context do
    now = DateTime.utc_now()
    rows = [[context.p1.slug, 1000, 1500, 20, 30, 100, 200, 3]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        get_github_activity_stats(
          context.conn,
          %{slugs: [context.p1.slug], map_as_input_object: true},
          Timex.beginning_of_day(now),
          now
        )
        |> get_in(["data", "githubActivityStats"])

      assert [%{"slug" => _, "devActivity" => 1000}] = data
    end)
  end

  test "error when too many slugs are provided", context do
    slugs = Enum.map(1..101, fn i -> "slug-#{i}" end)

    %{"errors" => [error]} =
      get_github_activity_stats(
        context.conn,
        %{slugs: slugs, map_as_input_object: true},
        context.from,
        context.to
      )

    assert error["message"] =~ "more than 100 slugs"
  end

  defp get_github_activity_stats(conn, selector, from, to, extra_args \\ %{}) do
    args = Map.merge(%{selector: selector, from: from, to: to}, extra_args)

    query = """
    {
      githubActivityStats(#{map_to_args(args)}){
        slug
        devActivity
        githubActivity
        devActivityContributorsCount
        githubActivityContributorsCount
        botDevActivity
        botGithubActivity
        botContributorsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
