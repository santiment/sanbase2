defmodule Sanbase.Knowledge.Reranker.OpenRouterCohereTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Reranker.OpenRouterCohere

  defp candidates(),
    do: [
      %{id: "a", text: "first candidate", similarity: 0.9},
      %{id: "b", text: "second candidate", similarity: 0.8},
      %{id: "c", text: "third candidate", similarity: 0.7}
    ]

  defp stub_post(results) do
    fn _url, _opts ->
      {:ok, %{status: 200, body: %{"results" => results}}}
    end
  end

  describe "rerank/3 happy path" do
    test "applies the model-provided order by descending relevance_score" do
      post =
        stub_post([
          %{"index" => 2, "relevance_score" => 0.95},
          %{"index" => 0, "relevance_score" => 0.80},
          %{"index" => 1, "relevance_score" => 0.40}
        ])

      assert {:ok, [%{id: "c"}, %{id: "a"}, %{id: "b"}]} =
               OpenRouterCohere.rerank("any query", candidates(), http_post: post)
    end

    test "scores returned out of order still produce descending output" do
      post =
        stub_post([
          %{"index" => 0, "relevance_score" => 0.10},
          %{"index" => 1, "relevance_score" => 0.99},
          %{"index" => 2, "relevance_score" => 0.50}
        ])

      assert {:ok, [%{id: "b"}, %{id: "c"}, %{id: "a"}]} =
               OpenRouterCohere.rerank("q", candidates(), http_post: post)
    end

    test "empty candidate list short-circuits without an HTTP call" do
      post = fn _url, _opts -> raise "should not be called" end
      assert {:ok, []} = OpenRouterCohere.rerank("q", [], http_post: post)
    end
  end

  describe "apply_results/2 edge cases" do
    test "indices out of range are skipped" do
      result =
        OpenRouterCohere.apply_results(candidates(), [
          %{"index" => 99, "relevance_score" => 0.9},
          %{"index" => 0, "relevance_score" => 0.8}
        ])

      assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    end

    test "duplicate indices count once" do
      result =
        OpenRouterCohere.apply_results(candidates(), [
          %{"index" => 1, "relevance_score" => 0.9},
          %{"index" => 1, "relevance_score" => 0.5},
          %{"index" => 0, "relevance_score" => 0.4}
        ])

      assert Enum.map(result, & &1.id) == ["b", "a", "c"]
    end

    test "missing indices are appended in original order at the tail" do
      result =
        OpenRouterCohere.apply_results(candidates(), [
          %{"index" => 2, "relevance_score" => 0.9}
        ])

      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end

    test "non-integer indices are ignored" do
      result =
        OpenRouterCohere.apply_results(candidates(), [
          %{"index" => "junk", "relevance_score" => 0.9},
          %{"index" => nil, "relevance_score" => 0.8},
          %{"index" => 1, "relevance_score" => 0.5}
        ])

      assert Enum.map(result, & &1.id) == ["b", "a", "c"]
    end

    test "empty results returns original list" do
      result = OpenRouterCohere.apply_results(candidates(), [])
      assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    end

    test "accepts atom keys as well as string keys" do
      result =
        OpenRouterCohere.apply_results(candidates(), [
          %{index: 2, relevance_score: 0.9},
          %{index: 0, relevance_score: 0.5}
        ])

      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end
  end

  describe "rerank/3 error fallback semantics" do
    test "missing results key surfaces an error" do
      post = fn _url, _opts -> {:ok, %{status: 200, body: %{"something_else" => 1}}} end

      assert {:error, {:malformed_response, _}} =
               OpenRouterCohere.rerank("q", candidates(), http_post: post)
    end

    test "non-200 status surfaces an error" do
      post = fn _url, _opts -> {:ok, %{status: 401, body: %{"error" => "no key"}}} end

      assert {:error, {:http_status, 401}} =
               OpenRouterCohere.rerank("q", candidates(), http_post: post)
    end

    test "transport error surfaces an error" do
      post = fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end

      assert {:error, %Mint.TransportError{}} =
               OpenRouterCohere.rerank("q", candidates(), http_post: post)
    end
  end

  describe "build_request_body/3" do
    test "sets the cohere model identifier" do
      body = OpenRouterCohere.build_request_body("q", candidates())
      assert body["model"] == "cohere/rerank-v3.5"
    end

    test "includes the query verbatim" do
      body = OpenRouterCohere.build_request_body("how do I get an API key", candidates())
      assert body["query"] == "how do I get an API key"
    end

    test "emits documents as a flat list of strings" do
      body = OpenRouterCohere.build_request_body("q", candidates())
      assert body["documents"] == ["first candidate", "second candidate", "third candidate"]
    end

    test "top_n equals candidate count so all scores come back" do
      body = OpenRouterCohere.build_request_body("q", candidates())
      assert body["top_n"] == 3
    end

    test "truncates very long candidate text" do
      long_text = String.duplicate("x", 1500)

      body =
        OpenRouterCohere.build_request_body("q", [%{id: "z", text: long_text, similarity: 1.0}])

      [doc] = body["documents"]
      refute doc =~ String.duplicate("x", 1500)
      assert doc =~ "…"
    end

    test "uses overridden model" do
      body =
        OpenRouterCohere.build_request_body("q", candidates(), "cohere/rerank-multilingual-v3.5")

      assert body["model"] == "cohere/rerank-multilingual-v3.5"
    end
  end
end
