defmodule SanbaseWeb.Graphql.EntityModerationApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    moderator_user = insert(:user)
    role = insert(:role_san_moderator)
    user = insert(:user)

    {:ok, _} = Sanbase.Accounts.UserRole.create(moderator_user.id, role.id)

    Sanbase.Cache.clear_all()
    conn = setup_jwt_auth(build_conn(), user)
    moderator_conn = setup_jwt_auth(build_conn(), moderator_user)

    %{conn: conn, moderator_conn: moderator_conn, user: user, moderator_user: moderator_user}
  end

  describe "set deleted" do
    test "regular users cannot delete", context do
      watchlist = insert(:watchlist, type: :project)

      error_msg =
        moderate_delete(context.conn, :project_watchlist, watchlist.id)
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg == "unauthorized"
    end

    test "watchlist", context do
      %{moderator_conn: moderator_conn} = context

      watchlist = insert(:watchlist, type: :project)

      assert {:ok, _} = Sanbase.UserList.by_id(watchlist.id, [])

      assert %{"data" => %{"moderateDelete" => true}} =
               moderate_delete(moderator_conn, :project_watchlist, watchlist.id)

      assert {:error, error_msg} = Sanbase.UserList.by_id(watchlist.id, [])
      assert error_msg =~ "does not exist"
    end

    test "chart configuration", %{moderator_conn: moderator_conn} do
      config = insert(:chart_configuration, is_public: true)
      assert {:ok, _} = Sanbase.Chart.Configuration.by_id(config.id, [])

      assert %{"data" => %{"moderateDelete" => true}} =
               moderate_delete(moderator_conn, :chart_configuration, config.id)

      assert {:error, error_msg} = Sanbase.Chart.Configuration.by_id(config.id, [])

      assert error_msg =~ "does not exist"
    end

    test "user trigger", %{moderator_conn: moderator_conn} do
      user_trigger = insert(:user_trigger)

      assert {:ok, _} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])

      assert %{"data" => %{"moderateDelete" => true}} =
               moderate_delete(moderator_conn, :user_trigger, user_trigger.id)

      assert {:error, error_msg} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])

      assert error_msg =~ "does not exist"
    end

    defp moderate_delete(conn, entity_type, entity_id) do
      args_str =
        %{entity_type: entity_type, entity_id: entity_id}
        |> map_to_args()

      mutation = """
      mutation{
        moderateDelete(#{args_str})
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end
  end

  describe "set hidden" do
    test "regular users cannot hide", context do
      watchlist = insert(:watchlist, type: :project)

      error_msg =
        moderate_hide(context.conn, :project_watchlist, watchlist.id)
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg == "unauthorized"
    end

    test "watchlist", %{conn: conn, moderator_conn: moderator_conn} do
      watchlist = insert(:watchlist, is_public: true, type: :project)

      watchlist_id_str = "#{watchlist.id}"
      assert {:ok, _} = Sanbase.UserList.by_id(watchlist.id, [])

      assert %{
               "data" => [%{"projectWatchlist" => %{"id" => ^watchlist_id_str}}],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(conn, :project_watchlist)

      assert %{"data" => %{"moderateHide" => true}} =
               moderate_hide(moderator_conn, :project_watchlist, watchlist.id)

      SanbaseWeb.Graphql.Cache.clear_all()

      assert %{
               "data" => [],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 0,
                 "totalPagesCount" => 0
               }
             } = get_most_recent(conn, :project_watchlist)

      assert {:ok, _} = Sanbase.UserList.by_id(watchlist.id, [])
    end

    test "chart configuration", %{conn: conn, moderator_conn: moderator_conn} do
      config = insert(:chart_configuration, is_public: true)
      config_id = config.id
      assert {:ok, _} = Sanbase.Chart.Configuration.by_id(config.id, [])

      assert %{
               "data" => [%{"chartConfiguration" => %{"id" => ^config_id}}],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(conn, :chart_configuration)

      assert %{"data" => %{"moderateHide" => true}} =
               moderate_hide(moderator_conn, :chart_configuration, config.id)

      SanbaseWeb.Graphql.Cache.clear_all()

      assert %{
               "data" => [],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 0,
                 "totalPagesCount" => 0
               }
             } = get_most_recent(conn, :chart_configuration)

      assert {:ok, _} = Sanbase.Chart.Configuration.by_id(config.id, [])
    end

    test "user trigger", %{conn: conn, moderator_conn: moderator_conn} do
      user_trigger = insert(:user_trigger, is_public: true)
      user_trigger_id = user_trigger.id

      assert {:ok, _} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])

      assert %{
               "data" => [
                 %{"userTrigger" => %{"trigger" => %{"id" => ^user_trigger_id}}}
               ],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(conn, :user_trigger)

      assert %{"data" => %{"moderateHide" => true}} =
               moderate_hide(moderator_conn, :user_trigger, user_trigger.id)

      SanbaseWeb.Graphql.Cache.clear_all()

      assert %{
               "data" => [],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 0,
                 "totalPagesCount" => 0
               }
             } = get_most_recent(conn, :user_trigger)

      assert {:ok, _} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])
    end

    test "unbpuslish insight", %{conn: conn, moderator_conn: moderator_conn} do
      insight = insert(:published_post)
      insight_id = insight.id

      assert {:ok, post} = Sanbase.Insight.Post.by_id(insight.id, [])
      assert post.ready_state == Sanbase.Insight.Post.published()

      assert %{
               "data" => [%{"insight" => %{"id" => ^insight_id}}],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(conn, :insight)

      mutation = """
      mutation{
        moderateUnpublishInsight(insightId: #{insight.id})
      }
      """

      assert %{"data" => %{"moderateUnpublishInsight" => true}} =
               moderator_conn
               |> post("/graphql", mutation_skeleton(mutation))
               |> json_response(200)

      SanbaseWeb.Graphql.Cache.clear_all()

      assert {:ok, post} = Sanbase.Insight.Post.by_id(insight.id, [])
      assert post.ready_state == Sanbase.Insight.Post.draft()

      assert %{
               "data" => [],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 0,
                 "totalPagesCount" => 0
               }
             } = get_most_recent(conn, :insight)
    end

    test "moderators can still see hidden content", %{moderator_conn: moderator_conn} do
      # The hidden content is visible to moderators, so hidding it results only
      # in setting the `is_hidden` flag to `true`

      user_trigger = insert(:user_trigger, is_public: true)
      user_trigger_id = user_trigger.id

      assert {:ok, _} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])

      assert %{
               "data" => [
                 %{
                   "userTrigger" => %{
                     "trigger" => %{"id" => ^user_trigger_id, "isHidden" => false}
                   }
                 }
               ],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(moderator_conn, :user_trigger)

      assert %{"data" => %{"moderateHide" => true}} =
               moderate_hide(moderator_conn, :user_trigger, user_trigger.id)

      SanbaseWeb.Graphql.Cache.clear_all()

      assert %{
               "data" => [
                 %{
                   "userTrigger" => %{
                     "trigger" => %{"id" => ^user_trigger_id, "isHidden" => true}
                   }
                 }
               ],
               "stats" => %{
                 "currentPage" => 1,
                 "currentPageSize" => 10,
                 "totalEntitiesCount" => 1,
                 "totalPagesCount" => 1
               }
             } = get_most_recent(moderator_conn, :user_trigger)

      assert {:ok, _} = Sanbase.Alert.UserTrigger.by_id(user_trigger.id, [])
    end

    defp moderate_hide(conn, entity_type, entity_id) do
      args_str =
        %{entity_type: entity_type, entity_id: entity_id}
        |> map_to_args()

      mutation = """
      mutation{
        moderateHide(#{args_str})
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end

    defp get_most_recent(conn, entity_or_entities, opts \\ []) do
      opts =
        opts
        |> Keyword.put_new(:page, 1)
        |> Keyword.put_new(:page_size, 10)
        |> Keyword.put_new(:types, List.wrap(entity_or_entities))

      query = """
      {
        getMostRecent(#{map_to_args(Map.new(opts))}){
          stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
          data {
            insight{ id isHidden }
            projectWatchlist{ id isHidden }
            addressWatchlist{ id isHidden }
            screener{ id isHidden }
            chartConfiguration{ id isHidden }
            userTrigger{ trigger{ id isHidden } }
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "getMostRecent"])
    end
  end
end
