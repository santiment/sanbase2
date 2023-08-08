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
    project3 = insert(:random_erc20_project)

    {:ok, watchlist} = UserList.create_user_list(user, %{name: "test watchlist"})
    {:ok, watchlist2} = UserList.create_user_list(user, %{name: "test watchlist2"})

    {:ok, watchlist} =
      UserList.update_user_list(user, %{
        id: watchlist.id,
        list_items: [%{project_id: project1.id}, %{project_id: project2.id}]
      })

    {:ok,
     conn: conn,
     project1: project1,
     project2: project2,
     project3: project3,
     watchlist: watchlist,
     empty_watchlist: watchlist2}
  end

  test "no ticker or slug is trending", context do
    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: "1", score: 2},
           %{word: "2", score: 2}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{"trendingNames" => [], "trendingSlugs" => [], "trendingTickers" => []}
          }
        }
      }

      assert result == expected_result
    end
  end

  test "one of the slugs is trending", context do
    slug = context.project1.slug |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: slug, score: 2},
           %{word: "2", score: 2}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{
              "trendingNames" => [],
              "trendingSlugs" => [slug],
              "trendingTickers" => []
            }
          }
        }
      }

      assert result == expected_result
    end
  end

  test "one of the tickers is trending", context do
    ticker = context.project2.ticker |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: ticker, score: 2},
           %{word: "2", score: 2}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{
              "trendingNames" => [],
              "trendingSlugs" => [],
              "trendingTickers" => [ticker]
            }
          }
        }
      }

      assert result == expected_result
    end
  end

  test "both tickers and slugs are trending", context do
    ticker = context.project1.ticker |> String.downcase()
    slug = context.project1.slug |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: ticker, score: 1.5},
           %{word: slug, score: 5},
           %{word: "random", score: 10},
           %{word: "2", score: 2}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{
              "trendingNames" => [],
              "trendingSlugs" => [slug],
              "trendingTickers" => [ticker]
            }
          }
        }
      }

      assert result == expected_result
    end
  end

  test "name is trending", context do
    name = context.project1.name |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: name, score: 2},
           %{word: "random", score: 2},
           %{word: "2", score: 2}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      expected_result = %{
        "data" => %{
          "watchlist" => %{
            "stats" => %{
              "trendingSlugs" => [],
              "trendingTickers" => [],
              "trendingNames" => [name]
            }
          }
        }
      }

      assert result == expected_result
    end
  end

  test "two names are trending", context do
    name1 = context.project1.name |> String.downcase()
    name2 = context.project2.name |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: name1, score: 3},
           %{word: name2, score: 3},
           %{word: "2", score: 3}
         ]}
      end do
      result = fetch_watchlist_stats(context.conn, context.watchlist)

      %{"data" => %{"watchlist" => %{"stats" => %{"trendingNames" => names}}}} = result

      assert names |> Enum.sort() == [name1, name2] |> Enum.sort()
    end
  end

  test "trending projects fetched by name and ticker", context do
    name1 = context.project1.name |> String.downcase()
    ticker2 = context.project2.ticker |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: name1, score: 3},
           %{word: ticker2, score: 3},
           %{word: "something_random", score: 3}
         ]}
      end do
      result = fetch_watchlist_stats_trending_projects(context.conn, context.watchlist)

      %{"data" => %{"watchlist" => %{"stats" => %{"trendingProjects" => projects}}}} = result

      expected_result =
        [
          %{"slug" => context.project1.slug},
          %{"slug" => context.project2.slug}
        ]
        |> Enum.sort_by(fn %{"slug" => slug} -> slug end)

      projects_sorted = projects |> Enum.sort_by(fn %{"slug" => slug} -> slug end)

      assert projects_sorted == expected_result
    end
  end

  test "trending projects fetched by slug", context do
    slug = context.project1.slug |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: slug, score: 3},
           %{word: "something+random", score: 3}
         ]}
      end do
      result = fetch_watchlist_stats_trending_projects(context.conn, context.watchlist)

      %{"data" => %{"watchlist" => %{"stats" => %{"trendingProjects" => projects}}}} = result

      expected_result = [
        %{"slug" => context.project1.slug}
      ]

      assert projects == expected_result
    end
  end

  test "trending projects are uniq when slug, name and ticker are trending", context do
    slug = context.project1.slug |> String.downcase()
    name = context.project1.name |> String.downcase()
    ticker = context.project1.ticker |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: slug, score: 3},
           %{word: name, score: 4},
           %{word: ticker, score: 1},
           %{word: "random", score: 1}
         ]}
      end do
      result = fetch_watchlist_stats_trending_projects(context.conn, context.watchlist)

      %{"data" => %{"watchlist" => %{"stats" => %{"trendingProjects" => projects}}}} = result

      expected_result = [
        %{"slug" => context.project1.slug}
      ]

      assert projects == expected_result
    end
  end

  test "project not in watchlist is not included", context do
    slug = context.project1.slug |> String.downcase()
    name = context.project3.name |> String.downcase()
    ticker = context.project3.ticker |> String.downcase()
    slug2 = context.project3.slug |> String.downcase()

    with_mock Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: slug, score: 3},
           %{word: name, score: 4},
           %{word: ticker, score: 1},
           %{word: slug2, score: 1},
           %{word: "random", score: 1}
         ]}
      end do
      result = fetch_watchlist_stats_trending_projects(context.conn, context.watchlist)

      %{"data" => %{"watchlist" => %{"stats" => %{"trendingProjects" => projects}}}} = result

      expected_result = [
        %{"slug" => context.project1.slug}
      ]

      assert projects == expected_result
    end
  end

  defp fetch_watchlist_stats(conn, %{id: id}) do
    query = """
    {
      watchlist(id: #{id}){
        stats {
          trendingSlugs
          trendingTickers
          trendingNames
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "watchlist"))
    |> json_response(200)
  end

  defp fetch_watchlist_stats_trending_projects(conn, %{id: id}) do
    query = """
    {
      watchlist(id: #{id}){
        stats {
          trendingProjects {
            slug
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "watchlist"))
    |> json_response(200)
  end
end
