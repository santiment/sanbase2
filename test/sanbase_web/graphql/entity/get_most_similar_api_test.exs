defmodule SanbaseWeb.Graphql.GetMostSimilarApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  # Note: Similarity search is currently only implemented for insights.
  # Other entity types (dashboard, screener, etc.) are not supported.

  setup do
    _role = insert(:role_san_family)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  defp seconds_ago(seconds) do
    Timex.shift(DateTime.utc_now(), seconds: -seconds)
  end

  defp mock_embedding do
    List.duplicate(0.1, 1536)
  end

  defp create_post_embedding(post, embedding \\ nil) do
    embedding = embedding || mock_embedding()

    %Sanbase.Insight.PostEmbedding{}
    |> Sanbase.Insight.PostEmbedding.changeset(%{
      post_id: post.id,
      embedding: embedding,
      text_chunk:
        "Insight Title: #{post.title}\n\nChunk text from the insight: #{post.text || "Test content"}"
    })
    |> Sanbase.Repo.insert!()
  end

  test "get most similar insights", %{conn: conn} do
    insight1 =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        title: "Bitcoin price analysis",
        text: "This is a detailed analysis of Bitcoin prices",
        ready_state: "published",
        state: "approved"
      )

    insight2 =
      insert(:published_post,
        inserted_at: seconds_ago(25),
        title: "Ethereum market trends",
        text: "Analysis of Ethereum market trends",
        ready_state: "published",
        state: "approved"
      )

    insight3 =
      insert(:published_post,
        inserted_at: seconds_ago(20),
        title: "Crypto market overview",
        text: "Overview of the crypto market",
        ready_state: "published",
        state: "approved"
      )

    _unpublished = insert(:post, inserted_at: seconds_ago(15), ready_state: "draft")

    create_post_embedding(insight1)
    create_post_embedding(insight2)
    create_post_embedding(insight3)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_most_similar(conn, [:insight], ai_search_term: "bitcoin price")

      data = result["data"]
      stats = result["stats"]

      assert %{
               "totalEntitiesCount" => 3,
               "currentPage" => 1,
               "totalPagesCount" => 1,
               "currentPageSize" => 10
             } = stats

      assert length(data) == 3
      assert Enum.any?(data, fn item -> item["insight"]["id"] == insight1.id end)
      assert Enum.any?(data, fn item -> item["insight"]["id"] == insight2.id end)
      assert Enum.any?(data, fn item -> item["insight"]["id"] == insight3.id end)
    end)
  end

  test "get most similar insights with pagination", %{conn: conn} do
    insights =
      for i <- 1..10 do
        insert(:published_post,
          inserted_at: seconds_ago(30 - i),
          title: "Insight #{i}",
          text: "Content for insight #{i}",
          ready_state: "published",
          state: "approved"
        )
      end

    Enum.each(insights, &create_post_embedding/1)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "crypto analysis",
          page: 1,
          page_size: 5
        )

      data = result["data"]
      stats = result["stats"]

      assert %{
               "totalEntitiesCount" => 10,
               "currentPage" => 1,
               "totalPagesCount" => 2,
               "currentPageSize" => 5
             } = stats

      assert length(data) == 5

      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "crypto analysis",
          page: 2,
          page_size: 5
        )

      data = result["data"]
      stats = result["stats"]

      assert %{
               "totalEntitiesCount" => 10,
               "currentPage" => 2,
               "totalPagesCount" => 2,
               "currentPageSize" => 5
             } = stats

      assert length(data) == 5
    end)
  end

  test "get most similar insights for current user", %{conn: conn, user: user} do
    i1 =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        published_at: seconds_ago(30),
        title: "My insight 1",
        text: "My first insight content",
        user: user,
        ready_state: "published",
        state: "approved"
      )

    i2 =
      insert(:published_post,
        inserted_at: seconds_ago(25),
        published_at: seconds_ago(25),
        title: "My insight 2",
        text: "My second insight content",
        user: user,
        ready_state: "published",
        state: "approved"
      )

    other_user_insight =
      insert(:published_post,
        inserted_at: seconds_ago(20),
        title: "Other user insight",
        text: "Other user content",
        ready_state: "published",
        state: "approved"
      )

    create_post_embedding(i1)
    create_post_embedding(i2)
    create_post_embedding(other_user_insight)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "my insights",
          current_user_data_only: true
        )

      data = result["data"]
      stats = result["stats"]

      assert stats["totalEntitiesCount"] == 2
      assert length(data) == 2
      assert Enum.any?(data, fn item -> item["insight"]["id"] == i1.id end)
      assert Enum.any?(data, fn item -> item["insight"]["id"] == i2.id end)
    end)
  end

  test "get most similar multiple insights", %{conn: conn} do
    insight1 =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        title: "Bitcoin analysis",
        text: "Bitcoin analysis content",
        ready_state: "published",
        state: "approved"
      )

    insight2 =
      insert(:published_post,
        inserted_at: seconds_ago(20),
        title: "Market trends",
        text: "Market trends content",
        ready_state: "published",
        state: "approved"
      )

    insight3 =
      insert(:published_post,
        inserted_at: seconds_ago(15),
        title: "Crypto overview",
        text: "Crypto overview content",
        ready_state: "published",
        state: "approved"
      )

    insight4 =
      insert(:published_post,
        inserted_at: seconds_ago(10),
        title: "Trading strategies",
        text: "Trading strategies content",
        ready_state: "published",
        state: "approved"
      )

    create_post_embedding(insight1)
    create_post_embedding(insight2)
    create_post_embedding(insight3)
    create_post_embedding(insight4)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_most_similar(conn, [:insight], ai_search_term: "crypto analysis")

      data = result["data"]
      stats = result["stats"]

      assert stats["totalEntitiesCount"] >= 4
      assert length(data) >= 4

      insight_ids =
        data
        |> Enum.filter(&Map.has_key?(&1, "insight"))
        |> Enum.map(fn item -> item["insight"]["id"] end)

      assert insight1.id in insight_ids
      assert insight2.id in insight_ids
      assert insight3.id in insight_ids
      assert insight4.id in insight_ids
    end)
  end

  test "get most similar with filter", %{conn: conn} do
    insight1 =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        title: "Bitcoin price analysis",
        text: "Bitcoin price analysis content",
        tags: [build(:tag, name: "bitcoin"), build(:tag, name: "price")],
        ready_state: "published",
        state: "approved"
      )

    insight2 =
      insert(:published_post,
        inserted_at: seconds_ago(25),
        title: "Ethereum trends",
        text: "Ethereum trends content",
        tags: [build(:tag, name: "ethereum")],
        ready_state: "published",
        state: "approved"
      )

    create_post_embedding(insight1)
    create_post_embedding(insight2)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "bitcoin",
          filter: %{
            map_as_input_object: true,
            insight: %{
              map_as_input_object: true,
              tags: ["bitcoin"]
            }
          }
        )

      data = result["data"]
      stats = result["stats"]

      assert stats["totalEntitiesCount"] >= 1
      assert length(data) >= 1
      assert Enum.any?(data, fn item -> item["insight"]["id"] == insight1.id end)
    end)
  end

  test "get most similar total count", %{conn: conn} do
    insights =
      for i <- 1..5 do
        insert(:published_post,
          inserted_at: seconds_ago(30 - i),
          title: "Insight #{i}",
          text: "Content for insight #{i}",
          ready_state: "published",
          state: "approved"
        )
      end

    Enum.each(insights, &create_post_embedding/1)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "crypto",
          page: 1,
          page_size: 2
        )

      stats = result["stats"]

      assert %{
               "totalEntitiesCount" => 5,
               "currentPage" => 1,
               "totalPagesCount" => 3,
               "currentPageSize" => 2
             } = stats
    end)
  end

  test "get most similar with custom similarity_threshold", %{conn: conn} do
    insight1 =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        title: "Bitcoin price analysis",
        text: "Bitcoin price analysis content",
        ready_state: "published",
        state: "approved"
      )

    insight2 =
      insert(:published_post,
        inserted_at: seconds_ago(25),
        title: "Ethereum trends",
        text: "Ethereum trends content",
        ready_state: "published",
        state: "approved"
      )

    create_post_embedding(insight1)
    create_post_embedding(insight2)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [mock_embedding()]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # With the default threshold (0.4), both insights should be returned
      # since identical embeddings produce similarity = 1.0
      result =
        get_most_similar(conn, [:insight], ai_search_term: "bitcoin")

      assert length(result["data"]) == 2

      # With a very high threshold, all results should still be included
      # because identical embeddings produce similarity = 1.0
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "bitcoin",
          similarity_threshold: 0.99
        )

      assert length(result["data"]) == 2

      # With a threshold above 1.0, no results should be returned
      result =
        get_most_similar(conn, [:insight],
          ai_search_term: "bitcoin",
          similarity_threshold: 1.01
        )

      assert result["data"] == []
      assert result["stats"]["totalEntitiesCount"] == 0
    end)
  end

  test "get most similar returns error when embedding generation fails", %{conn: conn} do
    insight =
      insert(:published_post,
        inserted_at: seconds_ago(30),
        title: "Test insight",
        text: "Test content",
        ready_state: "published",
        state: "approved"
      )

    create_post_embedding(insight)

    Sanbase.Mock.prepare_mock2(&Sanbase.AI.Embedding.generate_embeddings/2, {:error, "API error"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      response =
        conn
        |> post(
          "/graphql",
          query_skeleton("""
          {
            getMostSimilar(types: [INSIGHT], aiSearchTerm: "test"){
              stats { totalEntitiesCount }
              data { insight{ id } }
            }
          }
          """)
        )
        |> json_response(200)

      assert %{
               "data" => %{"getMostSimilar" => nil},
               "errors" => errors
             } = response

      assert length(errors) >= 1

      assert Enum.any?(errors, fn error ->
               String.contains?(error["message"], "Failed to generate embeddings")
             end)
    end)
  end

  defp get_most_similar(conn, entity_or_entities, opts) do
    opts =
      opts
      |> Keyword.put_new(:page, 1)
      |> Keyword.put_new(:page_size, 10)
      |> Keyword.put_new(:types, List.wrap(entity_or_entities))
      |> Keyword.put_new(:min_title_length, 0)
      |> Keyword.put_new(:min_description_length, 0)

    args =
      case Map.new(opts) do
        %{filter: _} = map -> put_in(map, [:filter, :map_as_input_object], true)
        map -> map
      end

    query =
      """
      {
        getMostSimilar(#{map_to_args(args)}){
          stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
          data {
            addressWatchlist{ id insertedAt }
            chartConfiguration{ id insertedAt }
            dashboard{ id insertedAt }
            query{ id insertedAt }
            insight{ id insertedAt publishedAt }
            projectWatchlist{ id insertedAt }
            screener{ id views insertedAt }
            userTrigger{ trigger{ id insertedAt } }
          }
        }
      }
      """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostSimilar"])
  end
end
