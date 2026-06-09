defmodule Sanbase.AI.AcademyAIServiceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.AI.AcademyAIService
  alias Sanbase.Chat
  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  @embedding_size 1536

  setup do
    user = insert(:user)

    {:ok, chat} =
      Chat.create_chat(%{
        title: "Academy Test Chat",
        user_id: user.id,
        type: "academy_qa"
      })

    # Add some chat history
    {:ok, _msg1} = Chat.add_message_to_chat(chat.id, "What is DeFi?", :user, %{})

    {:ok, _msg2} =
      Chat.add_message_to_chat(
        chat.id,
        "DeFi stands for Decentralized Finance...",
        :assistant,
        %{}
      )

    %{
      user: user,
      chat: chat
    }
  end

  describe "semantic_search/2" do
    test "returns the matching academy chunks ordered by relevance, without LLM synthesis" do
      article =
        insert_article(
          title: "MVRV Guide",
          academy_url: "https://academy.santiment.net/metrics/mvrv/",
          github_path: "src/metrics/mvrv.md"
        )

      # The relevant chunk shares the query embedding (similarity ~1); the other
      # is orthogonal (similarity ~0), so vector search ranks the relevant one first.
      insert_chunk(article,
        chunk_index: 0,
        heading: "MVRV",
        content: "MVRV compares market value to realized value.",
        embedding: unit_vector(0)
      )

      insert_chunk(article,
        chunk_index: 1,
        heading: "Unrelated",
        content: "Something completely unrelated to the query.",
        embedding: unit_vector(5)
      )

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, [first, second]} = AcademyAIService.semantic_search("what is mvrv", top_k: 5)

        assert first.title == "MVRV Guide"
        assert first.url == "https://academy.santiment.net/metrics/mvrv/"
        assert first.heading == "MVRV"
        assert first.chunk == "MVRV compares market value to realized value."
        assert is_number(first.similarity)

        # The orthogonal chunk is still returned but ranks lower.
        assert second.heading == "Unrelated"
        assert first.similarity >= second.similarity
      end)
    end

    test "respects the :top_k option" do
      article = insert_article()

      for index <- 0..4 do
        insert_chunk(article,
          chunk_index: index,
          content: "Chunk #{index}",
          embedding: unit_vector(index)
        )
      end

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, results} = AcademyAIService.semantic_search("query", top_k: 2)
        assert length(results) == 2
      end)
    end

    test "returns an empty list when there are no academy chunks" do
      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, []} = AcademyAIService.semantic_search("query")
      end)
    end
  end

  # Helpers

  defp insert_article(attrs \\ []) do
    defaults = %{
      title: "Academy Article",
      academy_url: "https://academy.santiment.net/article/",
      github_path: "src/article.md",
      content_sha: "sha-#{System.unique_integer([:positive])}",
      is_stale: false
    }

    %AcademyArticle{}
    |> AcademyArticle.changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp insert_chunk(article, attrs) do
    attrs = Map.new(attrs)

    %AcademyArticleChunk{}
    |> AcademyArticleChunk.changeset(%{
      article_id: article.id,
      chunk_index: Map.fetch!(attrs, :chunk_index),
      heading: Map.get(attrs, :heading),
      content: Map.fetch!(attrs, :content),
      embedding: Map.fetch!(attrs, :embedding),
      is_stale: false
    })
    |> Repo.insert!()
  end

  # A unit vector with 1.0 at `index` and zeros elsewhere. Two unit vectors at
  # the same index are identical (cosine similarity 1); at different indices
  # they are orthogonal (cosine similarity 0).
  defp unit_vector(index) do
    List.duplicate(0.0, @embedding_size) |> List.replace_at(index, 1.0)
  end

  defp with_query_embedding(embedding, fun) do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [embedding]}
    )
    |> Sanbase.Mock.run_with_mocks(fun)
  end
end
