defmodule Sanbase.DeepResearch.EventParserTest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.EventParser

  describe "custom protocol events" do
    test "run_id" do
      assert EventParser.parse(%{"run_id" => "abc-123"}) == %{run_id: "abc-123"}
    end

    test "search_query carries phase + activity" do
      assert EventParser.parse(%{
               "type" => "search_query",
               "id" => "s1",
               "query" => "ETH staking yields"
             }) ==
               %{
                 phase: :researching,
                 activity: %{kind: :search_query, id: "s1", query: "ETH staking yields"}
               }
    end

    test "search_results maps results and defaults count to length" do
      result =
        EventParser.parse(%{
          "type" => "search_results",
          "id" => "s1",
          "query" => "ETH staking yields",
          "results" => [
            %{"title" => "T", "url" => "https://a.com/x", "domain" => "a.com", "snippet" => "s"}
          ]
        })

      assert %{phase: :researching, activity: activity} = result
      assert activity.kind == :search_results
      assert activity.count == 1

      assert [%{title: "T", url: "https://a.com/x", domain: "a.com", snippet: "s"}] =
               activity.results
    end

    test "mcp_call and mcp_result" do
      assert %{activity: %{kind: :mcp_call, tool: "get_metric", args: %{"slug" => "btc"}}} =
               EventParser.parse(%{
                 "type" => "mcp_call",
                 "id" => "m1",
                 "tool" => "get_metric",
                 "args" => %{"slug" => "btc"}
               })

      assert %{activity: %{kind: :mcp_result, ok: true, summary: "ok"}} =
               EventParser.parse(%{
                 "type" => "mcp_result",
                 "id" => "m1",
                 "tool" => "get_metric",
                 "ok" => true,
                 "summary" => "ok"
               })
    end

    test "clarification sets awaiting_user and filters blank questions" do
      assert EventParser.parse(%{
               "type" => "clarification",
               "questions" => ["Which region?", "", "What timeframe?"]
             }) ==
               %{
                 phase: :awaiting_user,
                 activity: %{
                   kind: :clarification,
                   questions: ["Which region?", "What timeframe?"]
                 }
               }
    end

    test "report event yields report markdown + writing phase" do
      assert EventParser.parse(%{"type" => "report", "markdown" => "# Title"}) ==
               %{report: "# Title", phase: :writing}

      assert EventParser.parse(%{"type" => "report", "markdown" => "  "}) == %{}
    end

    test "status error surfaces a top-level error" do
      assert %{error: "boom", activity: %{kind: :status, state: "error"}} =
               EventParser.parse(%{"type" => "status", "state" => "error", "detail" => "boom"})
    end

    test "status mcp_ready carries tools list" do
      assert %{activity: %{kind: :status, state: "mcp_ready", tools: ["a", "b"]}} =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "mcp_ready",
                 "tools" => ["a", "b"]
               })
    end

    test "skill event" do
      assert EventParser.parse(%{"type" => "skill", "name" => "defi", "path" => "/skills/defi"}) ==
               %{
                 phase: :researching,
                 activity: %{kind: :skill, name: "defi", path: "/skills/defi"}
               }
    end

    test "source event" do
      assert EventParser.parse(%{
               "type" => "source",
               "title" => "Ethereum Staking Guide",
               "url" => "https://ethereum.org/staking",
               "domain" => "ethereum.org"
             }) ==
               %{
                 activity: %{
                   kind: :source,
                   title: "Ethereum Staking Guide",
                   url: "https://ethereum.org/staking",
                   domain: "ethereum.org"
                 }
               }
    end
  end

  describe "santiment_meta" do
    test "mcp metadata is nested under :meta" do
      assert EventParser.parse(%{
               "santiment_meta" => %{"mcp_tool_calls" => 3, "mcp_configured" => true}
             }) ==
               %{meta: %{mcp_tool_calls: 3, mcp_configured: true}}
    end

    test "stream_error is surfaced at the top level as :error" do
      assert EventParser.parse(%{"santiment_meta" => %{"stream_error" => "rate limited"}}) ==
               %{error: "rate limited"}
    end
  end

  describe "values channel (updates)" do
    test "final_report" do
      assert EventParser.parse(%{"values" => %{"final_report" => "# Final"}}) ==
               %{report: "# Final", phase: :writing}
    end

    test "research_brief -> planning" do
      assert EventParser.parse(%{"values" => %{"research_brief" => "plan"}}) == %{
               phase: :planning
             }
    end

    test "nested node update with hint" do
      assert EventParser.parse(%{"research_supervisor" => %{"notes" => ["x"]}}) ==
               %{phase: :researching}
    end
  end

  describe "messages channel (thinking)" do
    test "ai message becomes a thinking snapshot" do
      assert EventParser.parse([
               %{"content" => "Let me analyze the network.", "type" => "ai", "id" => "m1"},
               %{"langgraph_node" => "research"}
             ]) ==
               %{thinking: %{id: "m1", text: "Let me analyze the network."}, phase: :researching}
    end

    test "tool messages are dropped" do
      assert EventParser.parse([%{"content" => "[1] raw result", "type" => "tool", "id" => "t1"}]) ==
               %{}
    end

    test "structured-output noise is dropped" do
      assert EventParser.parse([
               %{"content" => "need_clarification: true", "type" => "ai", "id" => "m1"}
             ]) == %{}
    end
  end

  test "unknown shapes are ignored" do
    assert EventParser.parse(%{"unrelated" => 1}) == %{}
    assert EventParser.parse("string") == %{}
  end
end
