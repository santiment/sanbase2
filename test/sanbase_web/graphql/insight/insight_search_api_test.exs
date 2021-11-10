defmodule SanbaseWeb.Graphql.InsightSearchApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.Post

  setup_all_with_mocks([
    {Sanbase.Notifications.Insight, [], [publish_in_discord: fn _ -> :ok end]}
  ]) do
    :ok
  end

  setup do
    clean_task_supervisor_children()
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    insert(:metric_postgres, name: "price_usd")

    # Use `create/2` instead of factory so the proper document_tokens update is issued
    {:ok, post1} =
      Post.create(user, %{
        title: "Combined metrics",
        text: "Article with mvrv and some realized value",
        metrics: ["price_usd", "mvrv_usd", "mvrv_usd_1d"],
        tags: ["MVRV"]
      })

    {:ok, post2} =
      Post.create(user, %{
        title: "MVRV undergoes",
        text: "Article with mvrv metric and explanation",
        tags: ["SAN", "BTC", "MVRV_USD", "MVRV"]
      })

    {:ok, post3} =
      Post.create(user, %{title: "NVT rockets", text: "Article with nvt", tags: ["SAN", "ETH"]})

    Post.publish(post1.id, user.id)
    Post.publish(post2.id, user.id)
    Post.publish(post3.id, user.id)

    %{conn: conn, user: user, post1: post1, post2: post2, post3: post3}
  end

  describe "Search without highlights" do
    test "search works with data in title", context do
      %{conn: conn, post2: post2} = context

      insights = search_insights(conn, "undergoes")
      assert length(insights) == 1
      insight = insights |> hd()
      assert insight["id"] |> String.to_integer() == post2.id
    end

    test "search works with data in metrics", context do
      %{conn: conn, post1: post1} = context

      insights = search_insights(conn, "price_usd")
      assert length(insights) == 1
      insight = insights |> hd()
      assert insight["id"] |> String.to_integer() == post1.id
    end

    test "search works with data in text", context do
      %{conn: conn, post1: post1, post2: post2} = context

      # also plural form are normalized
      insights = search_insights(conn, "explanations")
      assert length(insights) == 1
      insight = insights |> hd()
      assert insight["id"] |> String.to_integer() == post2.id

      # more than 1 insight
      insights = search_insights(conn, "mvrv")
      assert length(insights) == 2
      insight_ids = insights |> Enum.map(&(&1["id"] |> String.to_integer())) |> Enum.sort()
      assert post1.id in insight_ids
      assert post2.id in insight_ids
    end

    test "search multiple words ", context do
      %{conn: conn, post1: post1, post2: post2} = context

      # words are separated
      insights = search_insights(conn, "mvrv metric")

      assert length(insights) == 2
      insight_ids = insights |> Enum.map(&(&1["id"] |> String.to_integer())) |> Enum.sort()

      assert post1.id in insight_ids
      assert post2.id in insight_ids

      # words are exactly one after another

      insights = search_insights(conn, "metric explanations")
      assert length(insights) == 1
      insight = insights |> hd()
      assert insight["id"] |> String.to_integer() == post2.id
    end

    test "search works with data in tags", context do
      %{conn: conn, post2: post2, post3: post3} = context

      insights = search_insights(conn, "SAN")
      assert length(insights) == 2
      insight_ids = insights |> Enum.map(&(&1["id"] |> String.to_integer())) |> Enum.sort()
      assert post2.id in insight_ids
      assert post3.id in insight_ids
    end

    test "search priorities", context do
      %{conn: conn, user: user} = context

      {:ok, post1} = Post.create(user, %{title: "Uniswap in title", text: "Something here"})
      {:ok, post2} = Post.create(user, %{title: "title", text: "Uniswap here"})
      {:ok, post3} = Post.create(user, %{title: "title", text: "another here", tags: ["UNISWAP"]})

      Post.publish(post1.id, user.id)
      Post.publish(post2.id, user.id)
      Post.publish(post3.id, user.id)

      insights = search_insights(conn, "uniswap")
      insight_ids = Enum.map(insights, &(&1["id"] |> String.to_integer()))
      assert insight_ids == [post1.id, post3.id, post2.id]
    end

    test "partial match", context do
      %{conn: conn, user: user} = context

      {:ok, post1} = Post.create(user, %{title: "Uniswap in title", text: "Something here"})
      {:ok, post2} = Post.create(user, %{title: "title", text: "Uniswap here"})
      {:ok, post3} = Post.create(user, %{title: "title", text: "another here", tags: ["UNISWAP"]})

      Post.publish(post1.id, user.id)
      Post.publish(post2.id, user.id)
      Post.publish(post3.id, user.id)

      insights = search_insights(conn, "unisw")
      # Partial matching is done only in the title
      assert length(insights) == 3
      ids = Enum.map(insights, &String.to_integer(&1["id"]))

      # The posts are returned in order of rank
      assert ids == [post1.id, post3.id, post2.id]
    end

    defp search_insights(conn, search_term) do
      query = """
      {
        allInsightsBySearchTerm(searchTerm: "#{search_term}") {
          id
          tags{ name }
          metrics{ name }
          title
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "allInsightsBySearchTerm"])
    end
  end

  describe "search with highlights" do
    test "complete search with incomplete words does not match", context do
      %{conn: conn} = context
      # If the search term is an alphanumeric word it is considered incomplete.
      # if it has an interval, exact matches are returned
      list = search_insights_highlighted(conn, "mvr ")
      assert list == []
    end

    test "incomplete search with incomplete word matches", context do
      %{conn: conn} = context
      # If the search term is an alphanumeric word it is considered incomplete.
      # if it has an interval, exact matches are returned
      list = search_insights_highlighted(conn, "mvr")
      assert length(list) == 2
    end

    test "search with data in title - word `undergoes`", context do
      %{conn: conn, post2: post2} = context

      list = search_insights_highlighted(conn, "undergoes")
      assert length(list) == 1

      assert [%{"post" => post, "highlights" => highlights}] = list

      # Currently the tags string and the metrics string are ordered alphabetically
      # and not in order of creation
      assert highlights == %{
               "metrics" => [],
               "tags" => [%{"highlight" => false, "text" => "BTC MVRV MVRV_USD SAN"}],
               "text" => [
                 %{"highlight" => false, "text" => "Article with mvrv metric and explanation"}
               ],
               "title" => [
                 %{"highlight" => false, "text" => "MVRV "},
                 %{"highlight" => true, "text" => "undergoes"}
               ]
             }

      assert post == %{
               "id" => "#{post2.id}",
               "metrics" => [],
               "tags" => [
                 %{"name" => "MVRV"},
                 %{"name" => "SAN"},
                 %{"name" => "BTC"},
                 %{"name" => "MVRV_USD"}
               ],
               "title" => "MVRV undergoes"
             }
    end

    test "search with word in many places - word `mvrv`", context do
      %{conn: conn, post1: post1, post2: post2} = context

      list = search_insights_highlighted(conn, "mvrv")
      assert length(list) == 2

      assert [%{"post" => result_post1, "highlights" => result_highlights1}, _] = list
      assert [_, %{"post" => result_post2, "highlights" => result_highlights2}] = list

      assert result_highlights1 == %{
               "metrics" => [],
               "tags" => [
                 %{"highlight" => false, "text" => "BTC "},
                 %{"highlight" => true, "text" => "MVRV"},
                 %{"highlight" => false, "text" => " "},
                 %{"highlight" => true, "text" => "MVRV"},
                 %{"highlight" => false, "text" => "_USD SAN"}
               ],
               "text" => [
                 %{"highlight" => false, "text" => "Article with "},
                 %{"highlight" => true, "text" => "mvrv"},
                 %{"highlight" => false, "text" => " metric and explanation"}
               ],
               "title" => [
                 %{"highlight" => true, "text" => "MVRV"},
                 %{"highlight" => false, "text" => " undergoes"}
               ]
             }

      assert result_post1 == %{
               "id" => "#{post2.id}",
               "metrics" => [],
               "tags" => [
                 %{"name" => "MVRV"},
                 %{"name" => "SAN"},
                 %{"name" => "BTC"},
                 %{"name" => "MVRV_USD"}
               ],
               "title" => "MVRV undergoes"
             }

      assert result_highlights2 == %{
               "metrics" => [%{"highlight" => false, "text" => "price_usd"}],
               "tags" => [%{"highlight" => true, "text" => "MVRV"}],
               "text" => [
                 %{"highlight" => false, "text" => "Article with "},
                 %{"highlight" => true, "text" => "mvrv"},
                 %{"highlight" => false, "text" => " and some realized value"}
               ],
               "title" => [%{"highlight" => false, "text" => "Combined metrics"}]
             }

      assert result_post2 == %{
               "id" => "#{post1.id}",
               "metrics" => [%{"name" => "price_usd"}],
               "tags" => [%{"name" => "MVRV"}],
               "title" => "Combined metrics"
             }
    end

    # when there is an interval, then the query is considered completed and it wont
    # do any prefix matches
    test "search with data in metrics, search with complete query", context do
      %{conn: conn, post1: post1} = context

      # The metric is `price_usd`, but we search for the more commonly
      # written by humans `Price USD`
      list = search_insights_highlighted(conn, "Price USD")
      assert length(list) == 1
      assert [%{"post" => result_post1, "highlights" => result_highlights1}] = list

      assert result_highlights1 == %{
               "metrics" => [
                 %{"highlight" => true, "text" => "price"},
                 %{"highlight" => false, "text" => "_"},
                 %{"highlight" => true, "text" => "usd"}
               ],
               "tags" => [%{"highlight" => false, "text" => "MVRV"}],
               "text" => [
                 %{"highlight" => false, "text" => "Article with mvrv and some realized value"}
               ],
               "title" => [%{"highlight" => false, "text" => "Combined metrics"}]
             }

      assert result_post1 == %{
               "id" => "#{post1.id}",
               "metrics" => [%{"name" => "price_usd"}],
               "tags" => [%{"name" => "MVRV"}],
               "title" => "Combined metrics"
             }
    end

    test "search works with data in text", context do
      %{conn: conn, post2: post2} = context

      # also plural form are normalized
      list = search_insights_highlighted(conn, "explanations")
      assert length(list) == 1
      assert [%{"post" => result_post1, "highlights" => result_highlights1}] = list

      assert result_highlights1 == %{
               "metrics" => [],
               "tags" => [%{"highlight" => false, "text" => "BTC MVRV MVRV_USD SAN"}],
               "text" => [
                 %{"highlight" => false, "text" => "Article with mvrv metric and "},
                 %{"highlight" => true, "text" => "explanation"}
               ],
               "title" => [%{"highlight" => false, "text" => "MVRV undergoes"}]
             }

      assert result_post1 == %{
               "id" => "#{post2.id}",
               "metrics" => [],
               "tags" => [
                 %{"name" => "MVRV"},
                 %{"name" => "SAN"},
                 %{"name" => "BTC"},
                 %{"name" => "MVRV_USD"}
               ],
               "title" => "MVRV undergoes"
             }
    end

    test "search works with data in tags", context do
      %{conn: conn, post2: post2, post3: post3} = context

      list = search_insights_highlighted(conn, "SAN")
      assert length(list) == 2
      insight_ids = list |> Enum.map(&(&1["post"]["id"] |> String.to_integer())) |> Enum.sort()
      assert post2.id in insight_ids
      assert post3.id in insight_ids
    end

    test "search priorities", context do
      %{conn: conn, user: user} = context

      {:ok, post1} = Post.create(user, %{title: "Uniswap in title", text: "Something here"})
      {:ok, post2} = Post.create(user, %{title: "title", text: "Uniswap here"})
      {:ok, post3} = Post.create(user, %{title: "title", text: "another here", tags: ["UNISWAP"]})

      Post.publish(post1.id, user.id)
      Post.publish(post2.id, user.id)
      Post.publish(post3.id, user.id)

      list = search_insights_highlighted(conn, "uniswap")
      insight_ids = Enum.map(list, &(&1["post"]["id"] |> String.to_integer()))
      assert insight_ids == [post1.id, post3.id, post2.id]
    end

    test "partial match", context do
      %{conn: conn, user: user} = context

      {:ok, post1} = Post.create(user, %{title: "Uniswap in title", text: "Something here"})
      {:ok, post2} = Post.create(user, %{title: "title", text: "Uniswap here"})
      {:ok, post3} = Post.create(user, %{title: "title", text: "another here", tags: ["UNISWAP"]})

      Post.publish(post1.id, user.id)
      Post.publish(post2.id, user.id)
      Post.publish(post3.id, user.id)

      list = search_insights_highlighted(conn, "unisw")
      # Partial matching is done only in the title
      assert length(list) == 3
      ids = Enum.map(list, &String.to_integer(&1["post"]["id"]))

      # The posts are returned in order of rank
      assert ids == [post1.id, post3.id, post2.id]
    end

    defp search_insights_highlighted(conn, search_term) do
      query = """
      {
        allInsightsBySearchTermHighlighted(searchTerm: "#{search_term}") {
          post {
            id
            tags{ name }
            metrics{ name }
            title
          }
          highlights {
            title { highlight text }
            text { highlight text }
            tags { highlight text }
            metrics { highlight text }
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "allInsightsBySearchTermHighlighted"])
    end
  end
end
