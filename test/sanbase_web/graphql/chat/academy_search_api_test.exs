defmodule SanbaseWeb.Graphql.AcademySearchApiTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag :capture_log

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Middlewares.PublicRateLimit

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

  describe "academySearch input validation" do
    test "rejects a blank query" do
      error = execute_query_with_error(build_conn(), search_query("   ", 5), "academySearch")
      assert error =~ "must not be empty"
    end

    test "rejects a query longer than 1000 characters" do
      long = String.duplicate("a", 1001)
      error = execute_query_with_error(build_conn(), search_query(long, 5), "academySearch")
      assert error =~ "at most 1000 characters"
    end

    test "rejects topK outside 1..50" do
      for top_k <- [0, -1, 51, 100_000] do
        error =
          execute_query_with_error(build_conn(), search_query("mvrv", top_k), "academySearch")

        assert error =~ "topK must be between 1 and 50"
      end
    end

    test "does not leak upstream error details" do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.AI.Embedding.generate_embeddings/2,
        {:error, "OpenAI API error: 400 - {\"secret\": \"body\"}"}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error = execute_query_with_error(build_conn(), search_query("mvrv", 5), "academySearch")
        assert error == "Academy search is temporarily unavailable"
      end)
    end
  end

  describe "academySearch rate limit" do
    setup do
      original = Application.get_env(:sanbase, PublicRateLimit)

      Application.put_env(:sanbase, PublicRateLimit,
        academy_search: [
          anonymous: [{2, :timer.minutes(1)}, {3, :timer.hours(24)}],
          authenticated: [{4, :timer.minutes(1)}]
        ]
      )

      on_exit(fn -> Application.put_env(:sanbase, PublicRateLimit, original) end)
    end

    test "limits anonymous callers per remote IP" do
      conn = fn ->
        %{build_conn() | remote_ip: {10, 1, 2, System.unique_integer([:positive]) |> rem(250)}}
      end

      ip_conn = conn.()

      with_query_embedding(unit_vector(0), fn ->
        assert is_list(execute_query(ip_conn, search_query("mvrv", 5), "academySearch"))
        assert is_list(execute_query(ip_conn, search_query("mvrv", 5), "academySearch"))

        error = execute_query_with_error(ip_conn, search_query("mvrv", 5), "academySearch")
        assert error =~ "Rate limit exceeded"
      end)
    end

    test "a longer window limits a caller that stays under the per-minute limit" do
      Application.put_env(:sanbase, PublicRateLimit,
        academy_search: [anonymous: [{5, :timer.minutes(1)}, {3, :timer.hours(24)}]]
      )

      ip_conn = %{build_conn() | remote_ip: {10, 7, 7, 7}}

      with_query_embedding(unit_vector(0), fn ->
        for _ <- 1..3 do
          assert is_list(execute_query(ip_conn, search_query("mvrv", 5), "academySearch"))
        end

        error = execute_query_with_error(ip_conn, search_query("mvrv", 5), "academySearch")
        assert error =~ "Rate limit exceeded. Try again in"
        assert error =~ "hours"
      end)
    end

    test "authenticated callers get their own, higher limit" do
      user = insert(:user)
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      conn = %{build_conn() | remote_ip: {10, 9, 9, 9}} |> setup_apikey_auth(apikey)

      with_query_embedding(unit_vector(0), fn ->
        for _ <- 1..4 do
          assert is_list(execute_query(conn, search_query("mvrv", 5), "academySearch"))
        end

        error = execute_query_with_error(conn, search_query("mvrv", 5), "academySearch")
        assert error =~ "Rate limit exceeded"
      end)
    end
  end

  # Helpers

  defp search_query(query, top_k) do
    """
    {
      academySearch(query: #{inspect(query)}, topK: #{top_k}) {
        title
        content
      }
    }
    """
  end

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
