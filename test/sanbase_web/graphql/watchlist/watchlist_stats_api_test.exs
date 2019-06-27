defmodule SanbaseWeb.Graphql.WatchlistStatsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.UserList

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    project1 = insert(:random_erc20_project)
    project2 = insert(:random_erc20_project)

    {:ok, watchlist} = UserList.create_user_list(user, %{name: "test watchlist"})
    {:ok, watchlist2} = UserList.create_user_list(user, %{name: "test watchlist2"})

    {:ok, watchlist} =
      UserList.update_user_list(%{
        id: watchlist.id,
        list_items: [%{project_id: project1.id}, %{project_id: project2.id}]
      })

    {:ok,
     conn: conn,
     project1: project1,
     project2: project2,
     watchlist: watchlist,
     empty_watchlist: watchlist2}
  end

  test "no ticker or slug is trending", context do
    with_mock Sanbase.SocialData.TrendingWords,
      get_trending_now: fn _ ->
        ["1", "2"]
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{"stats" => %{"trendingSlugs" => [], "trendingTickers" => []}}
        }
      }

      assert result == expected_result
    end
  end

  test "one of the slugs is trending", context do
    slug = context.project1.coinmarketcap_id |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_trending_now: fn _ ->
        [slug, "2"]
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{"stats" => %{"trendingSlugs" => [slug], "trendingTickers" => []}}
        }
      }

      assert result == expected_result
    end
  end

  test "one of the tickers is trending", context do
    ticker = context.project2.ticker |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_trending_now: fn _ ->
        [ticker, "2"]
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{"stats" => %{"trendingSlugs" => [], "trendingTickers" => [ticker]}}
        }
      }

      assert result == expected_result
    end
  end

  test "both tickers and slugs are trending", context do
    ticker = context.project1.ticker |> String.downcase()
    slug = context.project1.coinmarketcap_id |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_trending_now: fn _ ->
        [ticker, slug, "random", "2"]
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{"trendingSlugs" => [slug], "trendingTickers" => [ticker]}
          }
        }
      }

      assert result == expected_result
    end
  end

  defp fetch_watchlist_stats(conn, %{id: id}) do
    query = """
    {
      watchlist(id: #{id}){
        stats {
          trendingSlugs
          trendingTickers
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "watchlist"))
    |> json_response(200)
  end
end
