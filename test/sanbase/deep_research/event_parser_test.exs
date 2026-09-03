defmodule Sanbase.DeepResearch.EventParserTest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.EventParser

  describe "custom protocol events" do
    test "run metadata: a worker picked the run up, so it leaves the queue" do
      assert %{
               run_id: "abc-123",
               phase: :planning,
               activity: %{kind: :status, state: "run_started", attempt: 1}
             } = EventParser.parse(%{"run_id" => "abc-123", "attempt" => 1})
    end

    test "run metadata on a later attempt: the server re-ran the run after a restart" do
      assert %{
               run_id: "abc-123",
               phase: :planning,
               activity: %{kind: :status, state: "run_restarted", attempt: 2}
             } = EventParser.parse(%{"run_id" => "abc-123", "attempt" => 2})
    end

    test "run metadata without an attempt counts as the first start" do
      assert %{run_id: "abc-123", activity: %{state: "run_started", attempt: 1}} =
               EventParser.parse(%{"run_id" => "abc-123"})
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

    test "custom-tool tool_call/tool_result render like mcp calls" do
      assert %{activity: %{kind: :mcp_call, tool: "social_messages", args: %{"asset" => "btc"}}} =
               EventParser.parse(%{
                 "type" => "tool_call",
                 "id" => "t1",
                 "tool" => "social_messages",
                 "args" => %{"asset" => "btc"}
               })

      assert %{activity: %{kind: :mcp_result, ok: true, summary: "done"}} =
               EventParser.parse(%{
                 "type" => "tool_result",
                 "id" => "t1",
                 "tool" => "social_messages",
                 "ok" => true,
                 "summary" => "done"
               })
    end

    test "web_fetch tool_call/tool_result become page-read rows, keyed by url" do
      assert EventParser.parse(%{
               "type" => "tool_call",
               "id" => "f1",
               "tool" => "web_fetch",
               "args" => %{"url" => "https://example.com/report"}
             }) ==
               %{
                 phase: :researching,
                 activity: %{kind: :fetch_call, id: "f1", url: "https://example.com/report"}
               }

      assert EventParser.parse(%{
               "type" => "tool_result",
               "id" => "f1",
               "tool" => "web_fetch",
               "ok" => true,
               "summary" => "Fetched 12k chars"
             }) ==
               %{
                 activity: %{
                   kind: :fetch_result,
                   id: "f1",
                   ok: true,
                   summary: "Fetched 12k chars"
                 }
               }
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

    test "status error keeps the agent's detail, which now ends with its run time" do
      detail = "Hit the run budget before delivering a report. Run time 4m 12s."

      assert %{
               error: ^detail,
               activity: %{kind: :status, state: "error", reason: "budget_exhausted"}
             } =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "error",
                 "reason" => "budget_exhausted",
                 "detail" => detail,
                 "elapsed_s" => 252.4,
                 "elapsed" => "4m 12s"
               })
    end

    test "status rows keep the per-state facts the transcript quotes" do
      assert %{
               activity: %{
                 kind: :status,
                 state: "compacted",
                 tokens_estimate: 120_000,
                 messages_summarized: 40
               }
             } =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "compacted",
                 "tokens_estimate" => 120_000,
                 "messages_summarized" => 40,
                 "messages_kept" => 8
               })

      assert %{activity: %{kind: :status, state: "loop_detected", repeats: 3}} =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "loop_detected",
                 "repeats" => 3
               })

      assert %{
               activity: %{
                 kind: :status,
                 state: "revising",
                 reason: "report_quality",
                 detail: "2 uncited sources"
               }
             } =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "revising",
                 "reason" => "report_quality",
                 "detail" => "2 uncited sources"
               })
    end

    test "a status state this release does not know is a plain status row, never an error" do
      result =
        EventParser.parse(%{
          "type" => "status",
          "state" => "teleporting",
          "detail" => "beam me up"
        })

      assert %{activity: %{kind: :status, state: "teleporting", detail: "beam me up"}} = result
      refute Map.has_key?(result, :error)
    end

    test "usage becomes the run's ledger, preferring the fleet-wide token total" do
      assert EventParser.parse(%{
               "type" => "usage",
               "tool_calls" => 42,
               "model_calls" => 17,
               "total_tokens" => 300_000,
               "total_tokens_all_agents" => 380_000,
               "cost_usd" => 0.1234,
               "elapsed_s" => 252.4,
               "elapsed" => "4m 12s",
               "subagents" => %{"research-subagent" => %{"runs" => 3, "model_calls" => 9}},
               "limits" => %{"max_tool_calls" => 500}
             }) ==
               %{
                 activity: %{
                   kind: :usage,
                   elapsed_s: 252.4,
                   tool_calls: 42,
                   model_calls: 17,
                   total_tokens: 380_000,
                   cost_usd: 0.1234,
                   subagent_runs: 3
                 }
               }

      # A sparse ledger (older agent): missing numbers are nil, not crashes.
      assert %{activity: %{kind: :usage, total_tokens: 300, subagent_runs: 0, cost_usd: nil}} =
               EventParser.parse(%{"type" => "usage", "total_tokens" => 300})
    end

    test "run_start is ignored" do
      assert EventParser.parse(%{
               "type" => "run_start",
               "protocol_version" => 1,
               "engine_version" => "0.4.0",
               "started_at" => "2026-09-02T10:00:00Z"
             }) == %{}
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

    test "chart event carries phase + activity with series" do
      assert EventParser.parse(%{
               "type" => "chart",
               "id" => "c1",
               "slug" => "bitcoin",
               "range" => "90d",
               "series" => [
                 %{"style" => "candles", "pane" => 0, "data" => [%{"time" => 1, "close" => 2}]}
               ]
             }) ==
               %{
                 phase: :researching,
                 activity: %{
                   kind: :chart,
                   id: "c1",
                   slug: "bitcoin",
                   range: "90d",
                   summary: nil,
                   series: [
                     %{
                       "style" => "candles",
                       "pane" => 0,
                       "data" => [%{"time" => 1, "close" => 2}]
                     }
                   ]
                 }
               }
    end

    test "chart event with no usable series is ignored" do
      assert EventParser.parse(%{"type" => "chart", "id" => "c1", "series" => []}) == %{}
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

  describe "LangGraph stream error payloads" do
    test "a crashed run's error/message pair becomes the turn's error" do
      assert EventParser.parse(%{
               "error" => "GraphRecursionError",
               "message" => "Recursion limit of 1000 reached without hitting a stop condition."
             }) ==
               %{
                 error:
                   "The research agent failed (GraphRecursionError): " <>
                     "Recursion limit of 1000 reached without hitting a stop condition."
               }
    end

    test "an error class identical to its message is not repeated" do
      assert EventParser.parse(%{"error" => "timeout", "message" => "timeout"}) ==
               %{error: "The research agent failed: timeout"}
    end

    test "a very long message is cut" do
      %{error: err} =
        EventParser.parse(%{"error" => "E", "message" => String.duplicate("x", 1_000)})

      assert String.length(err) < 700
    end

    test "a protocol event that happens to carry error/message keys is not one" do
      assert %{activity: %{kind: :status, state: "mcp_ready"}} =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "mcp_ready",
                 "error" => "x",
                 "message" => "y"
               })
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

  describe "model_call heartbeat" do
    test "lands in :live with the role, model, step, brief and last tool results" do
      assert EventParser.parse(%{
               "type" => "status",
               "state" => "model_call",
               "role" => "research-subagent",
               "model" => "deepseek/deepseek-v4-flash",
               "step" => 4,
               "unit" => "Research BTC price for the last 90 days",
               "after" => "get_metric ×2",
               "after_chars" => 14_000
             }) ==
               %{
                 live: %{
                   kind: :model_call,
                   role: "research-subagent",
                   model: "deepseek/deepseek-v4-flash",
                   step: 4,
                   unit: "Research BTC price for the last 90 days",
                   after: "get_metric ×2",
                   after_chars: 14_000
                 }
               }
    end

    test "optional fields come back nil when the agent omits them" do
      assert %{live: %{unit: nil, after: nil, after_chars: nil, step: nil}} =
               EventParser.parse(%{
                 "type" => "status",
                 "state" => "model_call",
                 "role" => "orchestrator"
               })
    end
  end

  describe "messages channel (plan)" do
    test "a finished write_todos is a plan item, not a draft" do
      result =
        EventParser.parse([
          %{
            "content" => "",
            "type" => "ai",
            "tool_calls" => [
              %{
                "name" => "write_todos",
                "args" => %{
                  "todos" => [
                    %{"content" => "Fetch social volume", "status" => "completed"},
                    %{"content" => "Compute stats", "status" => "in_progress"},
                    %{"content" => "Write findings", "status" => "pending"},
                    "junk"
                  ]
                }
              }
            ]
          },
          %{}
        ])

      assert %{
               activity: %{
                 kind: :plan,
                 todos: [
                   %{content: "Fetch social volume", status: "completed"},
                   %{content: "Compute stats", status: "in_progress"},
                   %{content: "Write findings", status: "pending"}
                 ]
               }
             } = result

      refute Map.has_key?(result, :live)
    end

    test "a write_todos still streaming carries the complete items so far" do
      args =
        ~s({"todos":[{"content":"Fetch \\"social\\" volume","status":"completed"},{"content":"Compute st)

      assert %{live: %{name: "write_todos", todos: todos}} =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "invalid_tool_calls" => [
                     %{"name" => "write_todos", "args" => args, "error" => nil}
                   ]
                 },
                 %{}
               ])

      assert todos == [%{content: ~s(Fetch "social" volume), status: "completed"}]
    end

    test "a streaming call of another tool carries no todos" do
      assert %{live: live} =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "invalid_tool_calls" => [
                     %{"name" => "execute", "args" => ~s({"command":"ls), "error" => nil}
                   ]
                 },
                 %{}
               ])

      refute Map.has_key?(live, :todos)
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

    test "a tool call still being written becomes a live draft, not a thinking row" do
      args = ~s({"command": "python -c \"import json; rows = ['a', 'b', 'c')

      assert %{live: %{kind: :tool_call_draft, name: "execute", chars: chars, preview: preview}} =
               result =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "id" => "m2",
                   "invalid_tool_calls" => [
                     %{"name" => "execute", "args" => args, "error" => nil}
                   ]
                 },
                 %{}
               ])

      assert chars == byte_size(args)
      assert preview == args
      refute Map.has_key?(result, :thinking)
      refute Map.has_key?(result, :phase)
    end

    test "a long draft previews only its tail; a finished call (parsed args) previews too" do
      long = String.duplicate("x", 1_000)

      assert %{live: %{chars: 1_000, preview: "…" <> tail}} =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "tool_call_chunks" => [%{"name" => "execute", "args" => long}]
                 },
                 %{}
               ])

      assert String.length(tail) == 600

      assert %{live: %{name: "task", preview: ~s({"description":"Analyze ETH"})}} =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "tool_calls" => [
                     %{"name" => "task", "args" => %{"description" => "Analyze ETH"}}
                   ]
                 },
                 %{}
               ])
    end

    test "long string values are hidden from the preview, finished or still streaming" do
      content = String.duplicate("buy the dip ", 40)
      finished = ~s({"file_path":"/notes/btc.md","content":"#{content}"})
      streaming = ~s({"file_path":"/notes/btc.md","content":"#{content})

      assert %{live: %{chars: chars, preview: preview}} =
               EventParser.parse([draft("write_file", finished), %{}])

      assert chars == byte_size(finished)
      assert preview == ~s({"file_path":"/notes/btc.md","content":[480 chars]})

      assert %{live: %{preview: ~s({"file_path":"/notes/btc.md","content":[480 chars…])}} =
               EventParser.parse([draft("write_file", streaming), %{}])
    end

    test "an escaped quote inside a long value does not end the redaction early" do
      quoted = String.duplicate(~S(He said \"buy\" ), 20)
      args = ~s({"content":"#{quoted}","path":"/x.md"})

      assert %{live: %{preview: preview}} = EventParser.parse([draft("write_file", args), %{}])
      assert preview == ~s({"content":[#{String.length(quoted)} chars],"path":"/x.md"})
    end

    test "a finished call's parsed args are redacted the same way" do
      content = String.duplicate("sell everything ", 30)

      assert %{live: %{preview: preview}} =
               EventParser.parse([
                 %{
                   "content" => "",
                   "type" => "ai",
                   "tool_calls" => [
                     %{
                       "name" => "write_file",
                       "args" => %{"file_path" => "/notes/btc.md", "content" => content}
                     }
                   ]
                 },
                 %{}
               ])

      assert preview =~ ~s("file_path":"/notes/btc.md")
      assert preview =~ "[480 chars]"
      refute preview =~ "sell everything"
    end

    test "text plus a draft yields both the thinking row and the live preview" do
      assert %{thinking: %{text: "Let me check"}, live: %{name: "ls"}} =
               EventParser.parse([
                 %{
                   "content" => "Let me check",
                   "type" => "ai",
                   "id" => "m3",
                   "invalid_tool_calls" => [%{"name" => "ls", "args" => "{\"pa"}]
                 },
                 %{}
               ])
    end

    test "a message with neither text nor a draft is nothing" do
      assert EventParser.parse([%{"content" => "", "type" => "ai", "tool_calls" => []}, %{}]) ==
               %{}
    end

    test "tool messages are dropped" do
      assert EventParser.parse([%{"content" => "[1] raw result", "type" => "tool", "id" => "t1"}]) ==
               %{}
    end

    test "human messages (compaction summaries, loop nudges) are dropped" do
      assert EventParser.parse([
               %{
                 "content" => "[Context summary] Earlier the agent...",
                 "type" => "human",
                 "id" => "h1",
                 "name" => "dra_compaction_summary"
               }
             ]) == %{}
    end

    test "remove messages (compaction rewriting the state) are dropped" do
      assert EventParser.parse([%{"content" => "", "type" => "remove", "id" => "__remove_all__"}]) ==
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

  defp draft(name, args) do
    %{
      "content" => "",
      "type" => "ai",
      "invalid_tool_calls" => [%{"name" => name, "args" => args, "error" => nil}]
    }
  end
end
