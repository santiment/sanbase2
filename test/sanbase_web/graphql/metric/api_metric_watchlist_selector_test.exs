defmodule SanbaseWeb.Graphql.ApiMetricWatchlistSelectorTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @from ~U[2020-10-10 00:00:00Z]
  @to ~U[2020-10-12 00:00:00Z]

  setup do
    owner = insert(:user)
    other_user = insert(:user)
    project = insert(:random_project)

    private_watchlist = create_watchlist(owner, project, is_public: false, slug: "private-wl")
    public_watchlist = create_watchlist(owner, project, is_public: true, slug: "public-wl")

    rows = [[DateTime.to_unix(@from), project.slug, 100]]

    %{
      owner_conn: setup_jwt_auth(build_conn(), owner),
      other_conn: setup_jwt_auth(build_conn(), other_user),
      project: project,
      private_watchlist: private_watchlist,
      public_watchlist: public_watchlist,
      rows: rows
    }
  end

  describe "timeseriesDataPerSlug with a watchlist selector" do
    test "another user cannot use a private watchlist", context do
      result =
        query_with_mock(context, context.other_conn, watchlistId: context.private_watchlist.id)

      assert_private_watchlist_error(result)
    end

    test "an anonymous user cannot use a private watchlist", context do
      result = query_with_mock(context, build_conn(), watchlistId: context.private_watchlist.id)

      assert_private_watchlist_error(result)
    end

    test "another user cannot use a private watchlist by slug", context do
      result = query_with_mock(context, context.other_conn, watchlistSlug: "private-wl")

      assert_private_watchlist_error(result)
    end

    test "the owner can use their private watchlist", context do
      result =
        query_with_mock(context, context.owner_conn, watchlistId: context.private_watchlist.id)

      assert_project_data(result, context.project)
    end

    test "another user can use a public watchlist", context do
      result =
        query_with_mock(context, context.other_conn, watchlistId: context.public_watchlist.id)

      assert_project_data(result, context.project)

      result = query_with_mock(context, context.other_conn, watchlistSlug: "public-wl")
      assert_project_data(result, context.project)
    end

    test "a cached result of the owner is not served to another user", context do
      selector = [watchlistId: context.private_watchlist.id]

      result = query_with_mock(context, context.owner_conn, selector)
      assert_project_data(result, context.project)

      result = query_with_mock(context, context.other_conn, selector)
      assert_private_watchlist_error(result)
    end

    test "a cached result for a public watchlist is shared between users", context do
      selector = [watchlistId: context.public_watchlist.id]

      result = query_with_mock(context, context.owner_conn, selector)
      assert_project_value(result, 100.0)

      # A different DB result proves the second user is served from the cache
      context = %{context | rows: [[DateTime.to_unix(@from), context.project.slug, 999]]}
      result = query_with_mock(context, context.other_conn, selector)
      assert_project_value(result, 100.0)
    end
  end

  test "null watchlist arguments next to a slug are ignored", context do
    for null_arg <- ["watchlistSlug: null", "watchlistId: null"] do
      query = """
      {
        getMetric(metric: "price_usd") {
          timeseriesDataPerSlug(
            selector: {slug: "#{context.project.slug}", #{null_arg}}
            from: "#{@from}"
            to: "#{@to}"
            interval: "1d"
          ) {
            datetime
            data { slug value }
          }
        }
      }
      """

      result =
        Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: context.rows}})
        |> Sanbase.Mock.run_with_mocks(fn ->
          context.other_conn |> post("/graphql", query_skeleton(query)) |> json_response(200)
        end)

      assert_project_data(result, context.project)
    end

    assert Sanbase.Project.Selector.watchlist_references(%{
             selector: %{slug: "bitcoin", watchlist_id: nil, watchlist_slug: nil}
           }) == []

    assert Sanbase.Project.Selector.watchlist_references(%{
             selector: %{watchlist_id: nil, watchlist_slug: "private-wl"}
           }) == [{:watchlist_slug, "private-wl"}]

    assert Sanbase.Project.ListSelector.watchlist_base_projects(%{
             selector: %{base_projects: [%{watchlist_id: nil}, %{watchlist_slug: nil}]}
           }) == []
  end

  defp create_watchlist(user, project, opts) do
    watchlist = insert(:watchlist, [user: user] ++ opts)

    {:ok, watchlist} =
      Sanbase.UserList.update_user_list(user, %{
        id: watchlist.id,
        list_items: [%{project_id: project.id}]
      })

    watchlist
  end

  defp query_with_mock(context, conn, selector) do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: context.rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        getMetric(metric: "price_usd") {
          timeseriesDataPerSlug(
            selector: #{map_to_input_object_str(Map.new(selector))}
            from: "#{@from}"
            to: "#{@to}"
            interval: "1d"
          ) {
            datetime
            data { slug value }
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end)
  end

  defp assert_private_watchlist_error(result) do
    assert get_in(result, ["data", "getMetric", "timeseriesDataPerSlug"]) == nil
    assert [%{"message" => message}] = result["errors"]
    assert message =~ "does not exist or it is a private watchlist owned by another user"
  end

  defp assert_project_value(result, value) do
    refute Map.has_key?(result, "errors")

    assert [%{"data" => [%{"value" => ^value}]}] =
             get_in(result, ["data", "getMetric", "timeseriesDataPerSlug"])
  end

  defp assert_project_data(result, project) do
    refute Map.has_key?(result, "errors")

    assert [%{"data" => [%{"slug" => slug}]}] =
             get_in(result, ["data", "getMetric", "timeseriesDataPerSlug"])

    assert slug == project.slug
  end
end
