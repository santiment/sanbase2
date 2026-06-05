defmodule Sanbase.Knowledge.QueryPlanTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.QueryPlan

  # --- LLM client stubs ----------------------------------------------------
  # `build/2` accepts `:plan_llm_client` precisely so the LLM path is testable
  # without a network call. Injected clients skip the OPENAI_API_KEY check.

  defmodule TopicalClient do
    def ask(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         semantic_query: "bitcoin",
         has_topic: true,
         sort: "recency",
         last_n_days: nil,
         date_from: nil,
         date_to: nil
       })}
    end
  end

  defmodule BrowseClient do
    def ask(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         semantic_query: "insights",
         has_topic: false,
         # deliberately wrong: parse/3 must force :recency when has_topic=false
         sort: "relevance",
         last_n_days: nil,
         date_from: nil,
         date_to: nil
       })}
    end
  end

  defmodule WrongRelevanceClient do
    # Claims :relevance for a query with an explicit recency keyword — the
    # keyword floor must override it (observed gpt-5-nano failure mode).
    def ask(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         semantic_query: "bitcoin",
         has_topic: true,
         sort: "relevance",
         last_n_days: nil,
         date_from: nil,
         date_to: nil
       })}
    end
  end

  defmodule ErrorClient do
    def ask(_prompt, _opts), do: {:error, :boom}
  end

  defmodule MalformedClient do
    def ask(_prompt, _opts), do: {:ok, "this is not json"}
  end

  defmodule RaisingClient do
    def ask(_prompt, _opts), do: raise("kaboom")
  end

  defmodule SlowClient do
    def ask(_prompt, _opts) do
      Process.sleep(:timer.seconds(5))
      {:ok, "{}"}
    end
  end

  describe "build/2 (LLM path, stubbed client)" do
    test "uses the LLM plan when the call succeeds" do
      plan = QueryPlan.build("gimme the latest btc article", plan_llm_client: TopicalClient)

      assert plan.semantic_query == "bitcoin"
      assert plan.has_topic
      assert plan.sort == :recency
    end

    test "keyword floor: explicit recency cue overrides an LLM :relevance verdict" do
      plan =
        QueryPlan.build("Analyze the latest bitcoin insights",
          plan_llm_client: WrongRelevanceClient
        )

      assert plan.sort == :recency
      assert plan.semantic_query == "bitcoin"
    end

    test "keyword floor does not fire without a recency cue" do
      plan = QueryPlan.build("what is MVRV", plan_llm_client: WrongRelevanceClient)

      assert plan.sort == :relevance
    end

    test "browse plan: has_topic=false forces recency sort" do
      plan = QueryPlan.build("summarize the latest insights", plan_llm_client: BrowseClient)

      refute plan.has_topic
      assert plan.sort == :recency
    end

    test "client error falls back to the heuristic" do
      plan = QueryPlan.build("gimme newest btc article", plan_llm_client: ErrorClient)

      assert plan.sort == :recency
      refute plan.semantic_query =~ ~r/newest/i
      assert plan.semantic_query =~ "btc"
    end

    test "malformed JSON falls back to the heuristic" do
      plan = QueryPlan.build("gimme newest btc article", plan_llm_client: MalformedClient)

      assert plan.sort == :recency
      assert plan.semantic_query =~ "btc"
    end

    test "a crashing client is caught and falls back to the heuristic" do
      plan = QueryPlan.build("gimme newest btc article", plan_llm_client: RaisingClient)

      assert plan.sort == :recency
      assert plan.semantic_query =~ "btc"
    end

    test "a slow client is cut off at :plan_timeout_ms and falls back" do
      plan =
        QueryPlan.build("gimme newest btc article",
          plan_llm_client: SlowClient,
          plan_timeout_ms: 50
        )

      assert plan.sort == :recency
      assert plan.semantic_query =~ "btc"
    end
  end

  # `query_understanding: false` forces the deterministic heuristic path, so these
  # never make a network call regardless of whether OPENAI_API_KEY is set.
  describe "build/2 (heuristic path)" do
    test "recency query: strips recency words and sorts by recency" do
      plan = QueryPlan.build("gimme newest btc article", query_understanding: false)

      assert plan.sort == :recency
      assert plan.has_topic
      refute plan.semantic_query =~ ~r/newest/i
      assert plan.semantic_query =~ "btc"
      assert plan.date_from == nil
      assert plan.date_to == nil
    end

    test "non-recency query: kept as-is and sorts by relevance" do
      plan = QueryPlan.build("what is MVRV", query_understanding: false)

      assert plan.sort == :relevance
      assert plan.has_topic
      assert plan.semantic_query == "what is MVRV"
    end

    test "recency query with only generic words flags browse mode" do
      for query <- [
            "summarize the latest insights",
            "what's the latest insights",
            "show me the newest posts please"
          ] do
        plan = QueryPlan.build(query, query_understanding: false)

        refute plan.has_topic, "expected browse mode for: #{query}"
        assert plan.sort == :recency
      end
    end

    test "generic words WITHOUT a recency cue stay topical (browse needs both)" do
      plan = QueryPlan.build("show me insights", query_understanding: false)

      assert plan.has_topic
      assert plan.sort == :relevance
    end

    test "a recency query naming a topic is never browse mode" do
      plan = QueryPlan.build("latest bitcoin insights", query_understanding: false)

      assert plan.has_topic
      assert plan.sort == :recency
      assert plan.semantic_query =~ "bitcoin"
    end
  end

  describe "parse/3" do
    @today ~D[2026-06-10]

    defp llm_map(overrides) do
      Map.merge(
        %{
          "semantic_query" => "bitcoin",
          "has_topic" => true,
          "sort" => "recency",
          "last_n_days" => nil,
          "date_from" => nil,
          "date_to" => nil
        },
        overrides
      )
    end

    test "builds a plan from a valid map" do
      {:ok, plan} =
        QueryPlan.parse(
          llm_map(%{"date_from" => "2026-01-01"}),
          "gimme latest btc",
          @today
        )

      assert plan.semantic_query == "bitcoin"
      assert plan.has_topic
      assert plan.sort == :recency
      assert plan.date_from == ~D[2026-01-01]
      assert plan.date_to == nil
    end

    test "resolves last_n_days against `today` in Elixir, not in the LLM" do
      {:ok, plan} = QueryPlan.parse(llm_map(%{"last_n_days" => 7}), "raw", @today)

      assert plan.date_from == ~D[2026-06-03]
      assert plan.date_to == nil
    end

    test "an explicit date_from wins over last_n_days" do
      {:ok, plan} =
        QueryPlan.parse(
          llm_map(%{"last_n_days" => 7, "date_from" => "2026-01-01"}),
          "raw",
          @today
        )

      assert plan.date_from == ~D[2026-01-01]
    end

    test "non-positive or junk last_n_days is ignored" do
      for junk <- [0, -3, "7", 1.5] do
        {:ok, plan} = QueryPlan.parse(llm_map(%{"last_n_days" => junk}), "raw", @today)
        assert plan.date_from == nil
      end
    end

    test "has_topic=false forces sort to recency" do
      {:ok, plan} =
        QueryPlan.parse(
          llm_map(%{"has_topic" => false, "sort" => "relevance"}),
          "raw",
          @today
        )

      refute plan.has_topic
      assert plan.sort == :recency
    end

    test "missing or junk has_topic defaults to true" do
      for map <- [llm_map(%{}) |> Map.delete("has_topic"), llm_map(%{"has_topic" => "no"})] do
        {:ok, plan} = QueryPlan.parse(map, "raw", @today)
        assert plan.has_topic
      end
    end

    test "blank semantic_query falls back to the raw query" do
      {:ok, plan} = QueryPlan.parse(llm_map(%{"semantic_query" => "   "}), "raw query", @today)

      assert plan.semantic_query == "raw query"
    end

    test "unknown sort defaults to relevance and an unparseable date becomes nil" do
      {:ok, plan} =
        QueryPlan.parse(
          llm_map(%{"sort" => "whatever", "date_from" => "not-a-date"}),
          "raw",
          @today
        )

      assert plan.sort == :relevance
      assert plan.date_from == nil
    end

    test "non-map input returns :error so the caller can fall back" do
      assert QueryPlan.parse("nope", "raw", @today) == :error
    end
  end
end
