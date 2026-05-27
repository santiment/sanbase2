defmodule Sanbase.Knowledge.Reranker.LocalBgeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Reranker.LocalBge

  defp candidates(),
    do: [
      %{id: "a", text: "first candidate", similarity: 0.9},
      %{id: "b", text: "second candidate", similarity: 0.8},
      %{id: "c", text: "third candidate", similarity: 0.7}
    ]

  defp stub_post(body) do
    fn _url, _opts -> {:ok, %{status: 200, body: body}} end
  end

  describe "style/0" do
    test "declares :cross_encoder so the formatter strips Q:/A: labels" do
      assert LocalBge.style() == :cross_encoder
    end
  end

  describe "rerank/3 happy path with wrapped results" do
    test "Cohere/Infinity-style {results: [...]} body" do
      post =
        stub_post(%{
          "results" => [
            %{"index" => 2, "relevance_score" => 0.95},
            %{"index" => 0, "relevance_score" => 0.70},
            %{"index" => 1, "relevance_score" => 0.30}
          ]
        })

      assert {:ok, [%{id: "c"}, %{id: "a"}, %{id: "b"}]} =
               LocalBge.rerank("q", candidates(), http_post: post)
    end
  end

  describe "rerank/3 happy path with flat array results (TEI-style)" do
    test "flat list with score key" do
      post =
        stub_post([
          %{"index" => 1, "score" => 0.99},
          %{"index" => 2, "score" => 0.10},
          %{"index" => 0, "score" => 0.05}
        ])

      assert {:ok, [%{id: "b"}, %{id: "c"}, %{id: "a"}]} =
               LocalBge.rerank("q", candidates(), http_post: post)
    end
  end

  describe "rerank/3 short-circuit + errors" do
    test "empty candidates short-circuits with no HTTP call" do
      post = fn _url, _opts -> raise "should not be called" end
      assert {:ok, []} = LocalBge.rerank("q", [], http_post: post)
    end

    test "non-200 surfaces an error" do
      post = fn _url, _opts -> {:ok, %{status: 500, body: %{"error" => "boom"}}} end
      assert {:error, {:http_status, 500}} = LocalBge.rerank("q", candidates(), http_post: post)
    end

    test "malformed response surfaces an error" do
      post = stub_post(%{"something_else" => 1})

      assert {:error, {:malformed_response, _}} =
               LocalBge.rerank("q", candidates(), http_post: post)
    end

    test "transport error surfaces an error" do
      post = fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end

      assert {:error, %Mint.TransportError{}} =
               LocalBge.rerank("q", candidates(), http_post: post)
    end
  end

  describe "build_request_body/2" do
    test "matches the local server shape" do
      body = LocalBge.build_request_body("what is panda?", candidates())
      assert body["query"] == "what is panda?"
      assert body["documents"] == ["first candidate", "second candidate", "third candidate"]
      assert body["top_k"] == 3
      assert body["return_documents"] == false
    end

    test "truncates long candidate text" do
      long_text = String.duplicate("x", 1500)
      body = LocalBge.build_request_body("q", [%{id: "z", text: long_text, similarity: 1.0}])
      [doc] = body["documents"]
      refute doc =~ String.duplicate("x", 1500)
      assert doc =~ "…"
    end
  end

  describe "apply_results/2 edge cases" do
    test "indices out of range are skipped" do
      result =
        LocalBge.apply_results(candidates(), [
          %{"index" => 99, "relevance_score" => 0.9},
          %{"index" => 0, "relevance_score" => 0.8}
        ])

      assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    end

    test "duplicate indices count once" do
      result =
        LocalBge.apply_results(candidates(), [
          %{"index" => 1, "score" => 0.9},
          %{"index" => 1, "score" => 0.5},
          %{"index" => 0, "score" => 0.4}
        ])

      assert Enum.map(result, & &1.id) == ["b", "a", "c"]
    end

    test "missing indices are appended in original order" do
      result = LocalBge.apply_results(candidates(), [%{"index" => 2, "relevance_score" => 0.9}])
      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end

    test "empty results returns original list" do
      result = LocalBge.apply_results(candidates(), [])
      assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    end

    test "accepts atom keys" do
      result =
        LocalBge.apply_results(candidates(), [
          %{index: 2, score: 0.9},
          %{index: 0, relevance_score: 0.5}
        ])

      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end
  end

  describe "url override" do
    test "uses url from opts when provided" do
      seen_url = :ets.new(:seen, [:public])

      post = fn url, _opts ->
        :ets.insert(seen_url, {:url, url})
        {:ok, %{status: 200, body: %{"results" => []}}}
      end

      LocalBge.rerank("q", candidates(), http_post: post, url: "http://other:9000/rerank")

      assert [{:url, "http://other:9000/rerank"}] = :ets.lookup(seen_url, :url)
    end
  end
end
