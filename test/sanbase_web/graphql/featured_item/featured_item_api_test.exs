defmodule Sanbase.FeaturedItemApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.FeaturedItem
  alias Sanbase.Insight.Post

  describe "chart configuration featured items" do
    test "no chart configurations are featured", context do
      assert chart_configurations(context.conn) == %{
               "data" => %{"featuredChartConfigurations" => []}
             }
    end

    test "marking watchlists as featured", context do
      chart_configuration = insert(:chart_configuration, is_public: true)

      :ok = FeaturedItem.update_item(chart_configuration, true)

      assert chart_configurations(context.conn) == %{
               "data" => %{
                 "featuredChartConfigurations" => [
                   %{
                     "id" => chart_configuration.id,
                     "title" => "#{chart_configuration.title}"
                   }
                 ]
               }
             }
    end

    test "unmarking chart configurations as featured", context do
      chart_configuration = insert(:chart_configuration, is_public: true)
      :ok = FeaturedItem.update_item(chart_configuration, true)
      :ok = FeaturedItem.update_item(chart_configuration, false)

      assert chart_configurations(context.conn) == %{
               "data" => %{"featuredChartConfigurations" => []}
             }
    end

    test "marking chart configuration as featured is idempotent", context do
      chart_configuration = insert(:chart_configuration, is_public: true)
      :ok = FeaturedItem.update_item(chart_configuration, true)
      :ok = FeaturedItem.update_item(chart_configuration, true)
      :ok = FeaturedItem.update_item(chart_configuration, true)

      assert chart_configurations(context.conn) == %{
               "data" => %{
                 "featuredChartConfigurations" => [
                   %{
                     "id" => chart_configuration.id,
                     "title" => "#{chart_configuration.title}"
                   }
                 ]
               }
             }
    end

    defp chart_configurations(conn) do
      query = """
      {
        featuredChartConfigurations{
          id
          title
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end
  end

  describe "insight featured items" do
    test "no insights are featured", context do
      assert fetch_insights(context.conn) == %{
               "data" => %{"featuredInsights" => []}
             }
    end

    test "marking insights as featured", context do
      insight =
        insert(:post,
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      tags = insight.tags |> Enum.map(fn %{name: name} -> %{"name" => name} end)

      :ok = FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{
               "data" => %{
                 "featuredInsights" => [
                   %{
                     "id" => insight.id,
                     "title" => "#{insight.title}",
                     "tags" => tags
                   }
                 ]
               }
             }
    end

    test "ordering and pagination of featured insights works", context do
      insight1 = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      insight2 = insert(:post, state: Post.approved_state(), ready_state: Post.published())

      :ok = FeaturedItem.update_item(insight2, true)
      :ok = FeaturedItem.update_item(insight1, true)

      query = "{featuredInsights(page: 1, page_size: 1){ id }}"
      assert execute_query(context.conn, query, "featuredInsights") == [%{"id" => insight1.id}]
    end

    test "Not published insight cannot be featured", context do
      insight = insert(:post)
      {:error, _} = FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{
               "data" => %{"featuredInsights" => []}
             }
    end

    test "unmarking insights as featured", context do
      insight =
        insert(:post,
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      :ok = FeaturedItem.update_item(insight, true)
      :ok = FeaturedItem.update_item(insight, false)

      assert fetch_insights(context.conn) == %{
               "data" => %{"featuredInsights" => []}
             }
    end

    test "marking insight as featured is idempotent", context do
      insight =
        insert(:post,
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      tags = insight.tags |> Enum.map(fn %{name: name} -> %{"name" => name} end)
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{
               "data" => %{
                 "featuredInsights" => [
                   %{
                     "id" => insight.id,
                     "title" => "#{insight.title}",
                     "tags" => tags
                   }
                 ]
               }
             }
    end

    defp fetch_insights(conn) do
      query = """
      {
        featuredInsights{
          id
          title
          tags{ name }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end
  end

  describe "watchlist featured items" do
    test "no watchlists are featured", context do
      assert fetch_watchlists(context.conn) == %{
               "data" => %{"featuredWatchlists" => []}
             }
    end

    test "marking watchlists as featured", context do
      watchlist = insert(:watchlist, is_public: true)
      :ok = FeaturedItem.update_item(watchlist, true)

      assert fetch_watchlists(context.conn) == %{
               "data" => %{
                 "featuredWatchlists" => [
                   %{"id" => "#{watchlist.id}", "name" => "#{watchlist.name}"}
                 ]
               }
             }
    end

    test "fetching featured screeners", context do
      screener = insert(:watchlist, is_public: true, is_screener: true)
      :ok = FeaturedItem.update_item(screener, true)

      assert fetch_screeners(context.conn) == %{
               "data" => %{
                 "featuredScreeners" => [
                   %{"id" => "#{screener.id}", "name" => "#{screener.name}"}
                 ]
               }
             }
    end

    test "by default it fetches only non screeners watchlists", context do
      screener = insert(:watchlist, is_public: true, is_screener: true)
      watchlist = insert(:watchlist, is_public: true)
      :ok = FeaturedItem.update_item(screener, true)
      :ok = FeaturedItem.update_item(watchlist, true)

      assert fetch_watchlists(context.conn) == %{
               "data" => %{
                 "featuredWatchlists" => [
                   %{"id" => "#{watchlist.id}", "name" => "#{watchlist.name}"}
                 ]
               }
             }
    end

    test "unmarking watchlists as featured", context do
      watchlist = insert(:watchlist, is_public: true)
      :ok = FeaturedItem.update_item(watchlist, true)
      :ok = FeaturedItem.update_item(watchlist, false)

      assert fetch_watchlists(context.conn) == %{
               "data" => %{"featuredWatchlists" => []}
             }
    end

    test "marking watchlist as featured is idempotent", context do
      watchlist = insert(:watchlist, is_public: true)
      :ok = FeaturedItem.update_item(watchlist, true)
      :ok = FeaturedItem.update_item(watchlist, true)
      :ok = FeaturedItem.update_item(watchlist, true)

      assert fetch_watchlists(context.conn) == %{
               "data" => %{
                 "featuredWatchlists" => [
                   %{"id" => "#{watchlist.id}", "name" => "#{watchlist.name}"}
                 ]
               }
             }
    end

    defp fetch_watchlists(conn) do
      query = """
      {
        featuredWatchlists{
          id
          name
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end

    defp fetch_screeners(conn) do
      query = """
      {
        featuredScreeners{
          id
          name
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end
  end

  describe "user_trigger featured items" do
    test "no user_triggers are featured", context do
      assert fetch_user_triggers(context.conn) == %{
               "data" => %{"featuredUserTriggers" => []}
             }
    end

    test "marking user_triggers as featured", context do
      user_trigger = insert(:user_trigger, is_public: true)
      :ok = FeaturedItem.update_item(user_trigger, true)

      assert fetch_user_triggers(context.conn) == %{
               "data" => %{
                 "featuredUserTriggers" => [
                   %{
                     "trigger" => %{
                       "id" => user_trigger.id,
                       "title" => user_trigger.trigger.title
                     }
                   }
                 ]
               }
             }
    end

    test "unmarking user_triggers as featured", context do
      user_trigger = insert(:user_trigger, is_public: true)
      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, false)

      assert fetch_user_triggers(context.conn) == %{
               "data" => %{"featuredUserTriggers" => []}
             }
    end

    test "marking user_trigger as featured is idempotent", context do
      user_trigger = insert(:user_trigger, is_public: true)
      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, true)

      assert fetch_user_triggers(context.conn) == %{
               "data" => %{
                 "featuredUserTriggers" => [
                   %{
                     "trigger" => %{
                       "id" => user_trigger.id,
                       "title" => user_trigger.trigger.title
                     }
                   }
                 ]
               }
             }
    end

    defp fetch_user_triggers(conn) do
      query = """
      {
        featuredUserTriggers{
          trigger
          {
            id
            title
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end
  end
end
