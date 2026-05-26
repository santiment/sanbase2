defmodule Sanbase.Knowledge.Reranker.OpenAITest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Reranker.OpenAI

  defp candidates(),
    do: [
      %{id: "a", text: "first candidate", similarity: 0.9},
      %{id: "b", text: "second candidate", similarity: 0.8},
      %{id: "c", text: "third candidate", similarity: 0.7}
    ]

  defp stub_post(content) do
    fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => content}}]
         }
       }}
    end
  end

  describe "rerank/3 happy path" do
    test "applies the model-provided order" do
      post = stub_post(~s({"order": [3, 1, 2]}))

      assert {:ok, [%{id: "c"}, %{id: "a"}, %{id: "b"}]} =
               OpenAI.rerank("any query", candidates(), http_post: post)
    end

    test "empty candidate list short-circuits without an HTTP call" do
      post = fn _url, _opts -> raise "should not be called" end
      assert {:ok, []} = OpenAI.rerank("q", [], http_post: post)
    end
  end

  describe "apply_order/2 edge cases" do
    test "indices out of range are skipped" do
      result = OpenAI.apply_order(candidates(), [3, 99, 1])
      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end

    test "duplicate indices count once" do
      result = OpenAI.apply_order(candidates(), [2, 2, 1])
      assert Enum.map(result, & &1.id) == ["b", "a", "c"]
    end

    test "missing indices are appended in original order at the tail" do
      result = OpenAI.apply_order(candidates(), [3])
      assert Enum.map(result, & &1.id) == ["c", "a", "b"]
    end

    test "non-integer entries are ignored" do
      result = OpenAI.apply_order(candidates(), [2, "junk", nil, 1])
      assert Enum.map(result, & &1.id) == ["b", "a", "c"]
    end

    test "empty order returns original list" do
      result = OpenAI.apply_order(candidates(), [])
      assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    end
  end

  describe "rerank/3 error fallback semantics" do
    test "malformed json content surfaces an error" do
      post = stub_post("not json at all")
      assert {:error, {:json_decode, _}} = OpenAI.rerank("q", candidates(), http_post: post)
    end

    test "missing order key surfaces an error" do
      post = stub_post(~s({"something_else": 1}))
      assert {:error, {:missing_order_key, _}} = OpenAI.rerank("q", candidates(), http_post: post)
    end

    test "non-200 status surfaces an error" do
      post = fn _url, _opts -> {:ok, %{status: 500, body: %{"error" => "boom"}}} end
      assert {:error, {:http_status, 500}} = OpenAI.rerank("q", candidates(), http_post: post)
    end

    test "transport error surfaces an error" do
      post = fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end
      assert {:error, %Mint.TransportError{}} = OpenAI.rerank("q", candidates(), http_post: post)
    end
  end

  describe "build_request_body/3" do
    test "sets the json response format" do
      body = OpenAI.build_request_body("q", candidates())
      assert body["response_format"] == %{"type" => "json_object"}
    end

    test "embeds query and candidates in user message" do
      body = OpenAI.build_request_body("how do I get an API key", candidates())
      [_system, user] = body["messages"]
      assert user["content"] =~ "how do I get an API key"
      assert user["content"] =~ ~s(<Candidate id="1">)
      assert user["content"] =~ ~s(<Candidate id="3">)
      assert user["content"] =~ "first candidate"
    end

    test "truncates very long candidate text" do
      long_text = String.duplicate("x", 1500)
      body = OpenAI.build_request_body("q", [%{id: "z", text: long_text, similarity: 1.0}])
      [_system, user] = body["messages"]
      refute user["content"] =~ String.duplicate("x", 1500)
      assert user["content"] =~ "…"
    end

    test "uses overridden model" do
      body = OpenAI.build_request_body("q", candidates(), "some-other-model")
      assert body["model"] == "some-other-model"
    end
  end
end
