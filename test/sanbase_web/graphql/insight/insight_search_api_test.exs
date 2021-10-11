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
        metrics: ["price_usd"]
      })

    {:ok, post2} =
      Post.create(user, %{
        title: "MVRV undergoes",
        text: "Article with mvrv metric and explanation",
        tags: ["SAN", "BTC"]
      })

    {:ok, post3} =
      Post.create(user, %{title: "NVT rockets", text: "Article with nvt", tags: ["SAN", "ETH"]})

    Post.publish(post1.id, user.id)
    Post.publish(post2.id, user.id)
    Post.publish(post3.id, user.id)

    %{conn: conn, user: user, post1: post1, post2: post2, post3: post3}
  end

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
