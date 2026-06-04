defmodule SanbaseWeb.Graphql.AcademySearchApiTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag :capture_log

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  @embedding_size 1536

  describe "academySearch query" do
    test "returns the most relevant academy chunks without LLM synthesis" do
      article =
        insert_article(
          title: "MVRV Guide",
          academy_url: "https://academy.santiment.net/metrics/mvrv/",
          github_path: "src/metrics/mvrv.md"
        )

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

      query = """
      {
        academySearch(query: "what is mvrv", topK: 5) {
          title
          url
          content
          heading
          similarity
        }
      }
      """

      with_query_embedding(unit_vector(0), fn ->
        # academySearch is public, no auth needed.
        result = execute_query(build_conn(), query, "academySearch")

        assert [first, second] = result

        assert first["title"] == "MVRV Guide"
        assert first["url"] == "https://academy.santiment.net/metrics/mvrv/"
        assert first["heading"] == "MVRV"
        assert first["content"] == "MVRV compares market value to realized value."
        assert is_number(first["similarity"])

        assert second["heading"] == "Unrelated"
        assert first["similarity"] >= second["similarity"]
      end)
    end

    test "respects the topK argument" do
      article = insert_article()

      for index <- 0..4 do
        insert_chunk(article,
          chunk_index: index,
          content: "Chunk #{index}",
          embedding: unit_vector(index)
        )
      end

      query = """
      {
        academySearch(query: "query", topK: 2) {
          content
        }
      }
      """

      with_query_embedding(unit_vector(0), fn ->
        result = execute_query(build_conn(), query, "academySearch")
        assert length(result) == 2
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
