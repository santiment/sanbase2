defmodule Sanbase.FeaturedItemApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.FeaturedItem
  alias Sanbase.Insight.Post

  describe "insight featured items" do
    test "no insights are featured", context do
      assert fetch_insights(context.conn) == %{"data" => %{"featuredInsights" => []}}
    end

    test "marking insights as featured", context do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{
               "data" => %{
                 "featuredInsights" => [
                   %{"id" => "#{insight.id}", "title" => "#{insight.title}"}
                 ]
               }
             }
    end

    test "Only approved and published insights can be featured", context do
      insight = insert(:post)
      FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{"data" => %{"featuredInsights" => []}}
    end

    test "unmarking insights as featured", context do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, false)
      assert fetch_insights(context.conn) == %{"data" => %{"featuredInsights" => []}}
    end

    test "marking insight as featured is idempotent", context do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)

      assert fetch_insights(context.conn) == %{
               "data" => %{
                 "featuredInsights" => [
                   %{"id" => "#{insight.id}", "title" => "#{insight.title}"}
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
      assert fetch_watchlists(context.conn) == %{"data" => %{"featuredWatchlists" => []}}
    end

    test "marking watchlists as featured", context do
      watchlist = insert(:watchlist)
      FeaturedItem.update_item(watchlist, true)

      assert fetch_watchlists(context.conn) == %{
               "data" => %{
                 "featuredWatchlists" => [
                   %{"id" => "#{watchlist.id}", "name" => "#{watchlist.name}"}
                 ]
               }
             }
    end

    test "unmarking watchlists as featured", context do
      watchlist = insert(:watchlist)
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, false)
      assert fetch_watchlists(context.conn) == %{"data" => %{"featuredWatchlists" => []}}
    end

    test "marking watchlist as featured is idempotent", context do
      watchlist = insert(:watchlist)
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, true)

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
  end

  describe "user_trigger featured items" do
    test "no user_triggers are featured", context do
      assert fetch_user_triggers(context.conn) == %{"data" => %{"featuredUserTriggers" => []}}
    end

    test "marking user_triggers as featured", context do
      user_trigger = insert(:user_trigger)
      FeaturedItem.update_item(user_trigger, true)

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
      user_trigger = insert(:user_trigger)
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, false)
      assert fetch_user_triggers(context.conn) == %{"data" => %{"featuredUserTriggers" => []}}
    end

    test "marking user_trigger as featured is idempotent", context do
      user_trigger = insert(:user_trigger)
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, true)

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
