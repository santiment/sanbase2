defmodule SanbaseWeb.Graphql.ProjectListWatchlistBaseProjectsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    owner = insert(:user)
    other_user = insert(:user)
    project = insert(:random_project)
    _not_in_watchlist = insert(:random_project)

    private_watchlist = create_watchlist(owner, project, is_public: false, slug: "private-wl")
    public_watchlist = create_watchlist(owner, project, is_public: true, slug: "public-wl")

    %{
      owner: owner,
      owner_conn: setup_jwt_auth(build_conn(), owner),
      other_conn: setup_jwt_auth(build_conn(), other_user),
      project: project,
      private_watchlist: private_watchlist,
      public_watchlist: public_watchlist
    }
  end

  describe "allProjects with a watchlist in baseProjects" do
    test "another user cannot use a private watchlist", context do
      base = %{watchlistId: context.private_watchlist.id}

      assert_private_watchlist_error(all_projects(context.other_conn, base))
      assert_private_watchlist_error(all_projects(build_conn(), base))

      assert_private_watchlist_error(
        all_projects(context.other_conn, %{watchlistSlug: "private-wl"})
      )
    end

    test "the owner can use their private watchlist", context do
      result = all_projects(context.owner_conn, %{watchlistId: context.private_watchlist.id})

      assert_project_slugs(result, "allProjects", [context.project.slug])
    end

    test "another user can use a public watchlist", context do
      result = all_projects(context.other_conn, %{watchlistId: context.public_watchlist.id})
      assert_project_slugs(result, "allProjects", [context.project.slug])

      result = all_projects(context.other_conn, %{watchlistSlug: "public-wl"})
      assert_project_slugs(result, "allProjects", [context.project.slug])
    end

    test "a cached result of the owner is not served to another user", context do
      base = %{watchlistId: context.private_watchlist.id}

      result = all_projects(context.owner_conn, base)
      assert_project_slugs(result, "allProjects", [context.project.slug])

      assert_private_watchlist_error(all_projects(context.other_conn, base))
    end

    test "a cached result for a public watchlist is shared between users", context do
      base = %{watchlistId: context.public_watchlist.id}

      result = all_projects(context.owner_conn, base)
      assert_project_slugs(result, "allProjects", [context.project.slug])

      # A changed watchlist proves the second user is served from the cache
      new_project = insert(:random_project)

      {:ok, _} =
        Sanbase.UserList.update_user_list(context.owner, %{
          id: context.public_watchlist.id,
          list_items: [%{project_id: context.project.id}, %{project_id: new_project.id}]
        })

      result = all_projects(context.other_conn, base)
      assert_project_slugs(result, "allProjects", [context.project.slug])
    end
  end

  test "projectsCount with another user's private watchlist in baseProjects", context do
    query = """
    {
      projectsCount(selector: {baseProjects: [{watchlistId: #{context.private_watchlist.id}}]}) {
        projectsCount
      }
    }
    """

    assert_private_watchlist_error(execute(context.other_conn, query))
  end

  test "allProjectsByFunction with another user's private watchlist in baseProjects", context do
    function = %{
      "name" => "selector",
      "args" => %{"baseProjects" => [%{"watchlistId" => context.private_watchlist.id}]}
    }

    query = """
    {
      allProjectsByFunction(function: #{inspect(Jason.encode!(function))}) {
        projects { slug }
      }
    }
    """

    assert_private_watchlist_error(execute(context.other_conn, query))

    result = execute(context.owner_conn, query)
    refute Map.has_key?(result, "errors")

    assert [%{"slug" => slug}] = get_in(result, ["data", "allProjectsByFunction", "projects"])
    assert slug == context.project.slug
  end

  test "allProjectsByFunction with snake_case keys does not share a private result", context do
    function = %{
      "name" => "selector",
      "args" => %{"base_projects" => [%{"watchlist_id" => context.private_watchlist.id}]}
    }

    query = """
    {
      allProjectsByFunction(function: #{inspect(Jason.encode!(function))}) {
        projects { slug }
      }
    }
    """

    result = execute(context.owner_conn, query)
    refute Map.has_key?(result, "errors")
    assert [%{"slug" => slug}] = get_in(result, ["data", "allProjectsByFunction", "projects"])
    assert slug == context.project.slug

    assert_private_watchlist_error(execute(context.other_conn, query))

    assert Sanbase.WatchlistFunction.watchlist_references(function) ==
             [{:watchlist_id, context.private_watchlist.id}]
  end

  describe "saving a screener built on a private watchlist" do
    test "the owner can create and update one", context do
      function = base_projects_function(context.private_watchlist.id)

      assert {:ok, screener} =
               Sanbase.UserList.create_user_list(context.owner, %{
                 name: "My screener",
                 is_screener: true,
                 function: function
               })

      assert {:ok, _} =
               Sanbase.UserList.update_user_list(context.owner, %{
                 id: screener.id,
                 function: function
               })
    end

    test "another user cannot create one", context do
      other_user = insert(:user)

      assert {:error, changeset} =
               Sanbase.UserList.create_user_list(other_user, %{
                 name: "Not my screener",
                 is_screener: true,
                 function: base_projects_function(context.private_watchlist.id)
               })

      assert {message, _} = changeset.errors[:function]
      assert message =~ "private watchlist owned by another user"
    end
  end

  test "a public screener built on its owner's private watchlist works for other users",
       context do
    function = %{
      "name" => "selector",
      "args" => %{"baseProjects" => [%{"watchlistId" => context.private_watchlist.id}]}
    }

    screener =
      insert(:screener,
        user: context.owner,
        is_public: true,
        function: Sanbase.WatchlistFunction.cast(function) |> elem(1)
      )

    query = """
    {
      watchlist(id: #{screener.id}) {
        listItems { project { slug } }
      }
    }
    """

    result = execute(context.other_conn, query)
    refute Map.has_key?(result, "errors")

    assert [%{"project" => %{"slug" => slug}}] =
             get_in(result, ["data", "watchlist", "listItems"])

    assert slug == context.project.slug
  end

  defp base_projects_function(watchlist_id) do
    %{"name" => "selector", "args" => %{"baseProjects" => [%{"watchlistId" => watchlist_id}]}}
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

  defp all_projects(conn, base_project) do
    query = """
    {
      allProjects(selector: {baseProjects: [#{map_to_input_object_str(base_project)}]}) {
        slug
      }
    }
    """

    execute(conn, query)
  end

  defp execute(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp assert_private_watchlist_error(result) do
    assert [%{"message" => message}] = result["errors"]
    assert message =~ "does not exist or it is a private watchlist owned by another user"
  end

  defp assert_project_slugs(result, query_name, slugs) do
    refute Map.has_key?(result, "errors")
    assert Enum.map(get_in(result, ["data", query_name]), & &1["slug"]) == slugs
  end
end
