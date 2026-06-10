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

    test "browse plan: has_topic=false forces recency sort" do
      plan = QueryPlan.build("summarize the latest insights", plan_llm_client: BrowseClient)

      refute plan.has_topic
      assert plan.sort == :recency
    end

    # Every non-LLM path degrades to the same neutral pass-through plan: the
    # raw query embedded as-is, relevance sort, no dates — retrieval behaves
    # exactly as it did before query understanding existed.
    defp assert_passthrough(plan, user_input) do
      assert plan.semantic_query == user_input
      assert plan.sort == :relevance
      assert plan.has_topic
      assert plan.date_from == nil
      assert plan.date_to == nil
    end

    test "client error falls back to the pass-through plan" do
      input = "gimme newest btc article"

      plan = QueryPlan.build(input, plan_llm_client: ErrorClient)
      assert_passthrough(plan, input)
    end

    test "malformed JSON falls back to the pass-through plan" do
      input = "gimme newest btc article"

      plan = QueryPlan.build(input, plan_llm_client: MalformedClient)
      assert_passthrough(plan, input)
    end

    test "a crashing client is caught and falls back to the pass-through plan" do
      input = "gimme newest btc article"

      plan = QueryPlan.build(input, plan_llm_client: RaisingClient)
      assert_passthrough(plan, input)
    end

    test "a slow client is cut off at :plan_timeout_ms and falls back" do
      input = "gimme newest btc article"

      plan = QueryPlan.build(input, plan_llm_client: SlowClient, plan_timeout_ms: 50)
      assert_passthrough(plan, input)
    end

    test "query_understanding: false skips the LLM and passes the query through" do
      input = "Analyze the latest bitcoin insights"

      plan = QueryPlan.build(input, query_understanding: false)
      assert_passthrough(plan, input)
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
