defmodule SanbaseWeb.DeepResearch.ComponentsTest do
  @moduledoc """
  Render tests for the deep research presentation layer: the components directly (no
  mount, no auth, no DB), proving the HEEx renders for every timeline item kind and
  every phase — which compilation alone does not.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import SanbaseWeb.DeepResearch.Components

  alias Sanbase.DeepResearch.{Event, EventParser, Timeline}

  @now 1_700_000_000_000

  defp turn(results, overrides \\ %{}) do
    "What is driving ETH?"
    |> Timeline.new_turn(1, @now)
    |> then(
      &Enum.reduce(results, &1, fn result, acc -> Timeline.apply_result(acc, event(result)) end)
    )
    |> Map.merge(overrides)
  end

  # A test spells an event as the fields it fills; the parser already returns one.
  defp event(%Event{} = event), do: event
  defp event(attrs), do: struct!(Event, attrs)

  defp render_turn(turn, opts \\ []) do
    render_component(&turn_view/1,
      turn: turn,
      running: Keyword.get(opts, :running, false),
      now_ms: Keyword.get(opts, :now_ms),
      can_continue: Keyword.get(opts, :can_continue, false)
    )
  end

  describe "composer/1" do
    test "renders the question textarea and a submit button when idle" do
      html = render_component(&composer/1, query: "eth", running: false, placeholder: "Ask…")

      assert html =~ "Ask…"
      assert html =~ "eth"
      refute html =~ "phx-click=\"cancel\""
    end

    test "offers a cancel affordance while a run is in flight" do
      html = render_component(&composer/1, query: "", running: true, placeholder: "Ask…")

      assert html =~ "phx-click=\"cancel\""
    end
  end

  describe "turn_view/1" do
    test "always shows the question" do
      assert render_turn(turn([])) =~ "What is driving ETH?"
    end

    test "renders thinking narration" do
      html = render_turn(turn([%{thinking: %{id: "m1", text: "Planning the research"}}]))

      assert html =~ "Planning the research"
    end

    test "a fresh turn says it is queued on the agent server, not planning" do
      html = render_turn(turn([]), running: true, now_ms: @now + 3_000)

      assert html =~ "Queued on the agent server"
      refute html =~ "Planning research"
      assert html =~ "loading-spinner"
    end

    test "the run's metadata event moves the turn to planning and leaves a started row" do
      html =
        render_turn(turn([EventParser.parse(%{"run_id" => "r1", "attempt" => 1})]),
          running: true,
          now_ms: @now + 3_000
        )

      assert html =~ "Planning research"
      assert html =~ "Agent server picked up the run"
    end

    test "a re-run after a server restart shows the attempt" do
      html = render_turn(turn([EventParser.parse(%{"run_id" => "r1", "attempt" => 3})]))

      assert html =~ "Agent server restarted the run (attempt 3)"
    end

    test "a running turn says how long ago the stream last delivered anything" do
      fresh =
        render_turn(turn([], %{phase: :researching, last_event_at: @now + 9_000}),
          running: true,
          now_ms: @now + 10_000
        )

      assert fresh =~ "last event 1s ago"
      assert fresh =~ "animate-pulse"

      quiet =
        render_turn(turn([], %{phase: :researching, last_event_at: @now}),
          running: true,
          now_ms: @now + 4 * 60_000
        )

      assert quiet =~ "quiet for 4m 00s"
      assert quiet =~ "text-warning"

      stalled =
        render_turn(turn([], %{phase: :researching, last_event_at: @now}),
          running: true,
          now_ms: @now + 16 * 60_000
        )

      assert stalled =~ "no events for 16m 00s"
      assert stalled =~ "looks stalled, Stop and retry"
      assert stalled =~ "text-error"

      # Nothing received yet: counted from the question, calm at first.
      assert render_turn(turn([]), running: true, now_ms: @now + 5_000) =~ "no events yet"

      # A finished turn has no stream to report on.
      refute render_turn(
               turn([], %{phase: :completed, finished_at: @now + 5_000, last_event_at: @now})
             ) =~ "last event"
    end

    test "a series pasted into a finding is folded behind one expandable line" do
      series =
        Enum.map_join(5..20, "; ", fn d ->
          "2026-06-#{String.pad_leading("#{d}", 2, "0")},-0.20#{d}"
        end)

      findings = %{
        activity: %{
          kind: :subagent_findings,
          unit: "BTC MVRV",
          summary: "Fetched 16 daily MVRV points.",
          findings: [%{"finding" => "Complete daily series: " <> series, "source" => "Santiment"}],
          gaps: []
        }
      }

      html = render_turn(turn([findings], %{phase: :completed, report: "ok", finished_at: @now}))

      assert html =~ "16 points, 2026-06-05 → 2026-06-20 (collapsed)"
      assert html =~ "Complete daily series:"
      assert html =~ "hero-table-cells"
      # The numbers are still there, but inside a <details> the reader opens.
      assert html =~ "<details"
    end

    test "a model_call heartbeat says who is thinking and on what" do
      live = %{
        kind: :model_call,
        role: "research-subagent",
        model: "deepseek/deepseek-v4-flash",
        step: 4
      }

      html =
        render_turn(turn([], %{phase: :researching, live: live}),
          running: true,
          now_ms: @now + 1_000
        )

      assert html =~ "A research sub-agent is thinking"
      assert html =~ "deepseek/deepseek-v4-flash"
      assert html =~ "step 4"
      refute html =~ "show the raw call"
    end

    test "a streaming write_todos shows as a checklist under an 'Updating the plan' label" do
      live = %{
        kind: :tool_call_draft,
        name: "write_todos",
        chars: 533,
        preview: ~s({"todos":[...),
        todos: [
          %{content: "Fetch social volume", status: "completed"},
          %{content: "Compute summary statistics", status: "in_progress"},
          %{content: "Compile findings", status: "pending"}
        ]
      }

      html =
        render_turn(turn([], %{phase: :researching, live: live}),
          running: true,
          now_ms: @now + 1_000
        )

      assert html =~ "Updating the plan · 3 steps so far"
      refute html =~ "Preparing a"
      assert html =~ "Fetch social volume"
      assert html =~ "line-through"
      assert html =~ "hero-arrow-right-circle"
      assert html =~ "Compile findings"
    end

    test "a finished plan renders as a checklist block" do
      plan = %{
        activity: %{
          kind: :plan,
          todos: [
            %{content: "Fetch social volume", status: "completed"},
            %{content: "Compute summary statistics", status: "in_progress"}
          ]
        }
      }

      html = render_turn(turn([plan], %{phase: :completed, report: "ok", finished_at: @now}))

      assert html =~ ">Plan<" or html =~ "Plan\n"
      assert html =~ "hero-list-bullet"
      assert html =~ "Fetch social volume"
      assert html =~ "Compute summary statistics"
    end

    test "the tool call the model is still writing shows as a live draft with its tail" do
      live = %{
        kind: :tool_call_draft,
        name: "execute",
        chars: 14_521,
        preview: "'sensory', 'sensation', 'feeling'"
      }

      html =
        render_turn(turn([], %{phase: :researching, live: live}),
          running: true,
          now_ms: @now + 1_000
        )

      assert html =~ "Preparing a"
      assert html =~ "execute"
      assert html =~ "14.2 KB so far"
      assert html =~ "&#39;sensory&#39;, &#39;sensation&#39;, &#39;feeling&#39;"
      assert html =~ ~s(id="live-draft-1")

      refute render_turn(turn([], %{phase: :researching}), running: true, now_ms: @now) =~
               "Model is writing"
    end

    test "a paused turn shows the pause footer even with an empty timeline" do
      html = render_turn(turn([], %{phase: :paused, finished_at: @now + 5_000}))

      assert html =~ "Research paused"
      # Not the owner's resumable view — no Continue button.
      refute html =~ "phx-click=\"continue_turn\""
      refute html =~ "loading-spinner"
    end

    test "a continuable paused turn offers the Continue button" do
      html =
        render_turn(
          turn([%{thinking: %{id: "m1", text: "Scanning"}}], %{
            phase: :paused,
            finished_at: @now + 5_000
          }),
          can_continue: true
        )

      assert html =~ "Research paused"
      assert html =~ "phx-click=\"continue_turn\""
      assert html =~ "phx-value-id=\"1\""
      # The interrupted tool spinner settles — paused is inactive.
      refute html =~ "loading-spinner"
    end

    test "renders a search query with its results, linking only safe http(s) urls" do
      html =
        render_turn(
          turn([
            %{activity: %{kind: :search_query, id: "s1", query: "eth gas fees"}},
            %{
              activity: %{
                kind: :search_results,
                id: "s1",
                query: "eth gas fees",
                count: 2,
                results: [
                  %{
                    title: "Gas report",
                    url: "https://example.com/gas",
                    domain: "example.com",
                    snippet: nil
                  },
                  # A non-http scheme must render as plain text, never as a link.
                  %{title: "Sketchy", url: "javascript:alert(1)", domain: "", snippet: nil}
                ]
              }
            }
          ])
        )

      assert html =~ "eth gas fees"
      assert html =~ "https://example.com/gas"
      assert html =~ "Sketchy"
      refute html =~ "javascript:alert(1)"
    end

    test "renders mcp calls with a success or error status per call" do
      html =
        render_turn(
          turn([
            %{activity: %{kind: :mcp_call, id: "c1", tool: "fetch_metric_data", args: %{}}},
            %{activity: %{kind: :mcp_result, id: "c1", tool: "fetch_metric_data", ok: true}},
            %{activity: %{kind: :mcp_call, id: "c2", tool: "show_chart", args: %{}}},
            %{
              activity: %{
                kind: :mcp_result,
                id: "c2",
                tool: "show_chart",
                ok: false,
                summary: "tool exploded"
              }
            }
          ])
        )

      assert html =~ "fetch_metric_data"
      assert html =~ "hero-check-circle"
      assert html =~ "show_chart"
      assert html =~ "hero-x-circle"
      assert html =~ "tool exploded"
    end

    test "an unfinished call spins while running but settles neutrally once the turn ends" do
      # A call with no result: while the turn runs it is genuinely in flight, but
      # on a terminal turn it must NOT keep spinning forever — nor be shown as a
      # success or a failure, because the outcome is simply unknown.
      results = [%{activity: %{kind: :mcp_call, id: "c1", tool: "trending_stories", args: %{}}}]

      running = render_turn(turn(results), running: true, now_ms: @now)
      assert running =~ "loading-spinner"
      refute running =~ "Interrupted"

      # No spinner, no success check anywhere (not on the call row, not on either
      # enclosing group header) and no error cross — the outcome is unknown.
      cancelled = render_turn(turn(results, %{phase: :cancelled, finished_at: @now}))
      assert cancelled =~ "Interrupted"
      refute cancelled =~ "loading-spinner"
      refute cancelled =~ "hero-check-circle"
      refute cancelled =~ "hero-x-circle"
    end

    test "renders subagent findings" do
      html =
        render_turn(
          turn([
            %{
              activity: %{
                kind: :subagent_findings,
                unit: "on-chain",
                summary: "Fees fell 20%",
                findings: [%{"claim" => "Gas is down", "evidence" => "median fee 4 gwei"}],
                gaps: ["No L2 data"]
              }
            }
          ])
        )

      assert html =~ "Fees fell 20%"
      assert html =~ "Gas is down"
      assert html =~ "No L2 data"
    end

    test "renders a live timeline chart with its series payload" do
      html =
        render_turn(
          turn([
            %{
              activity: %{
                kind: :chart,
                id: "ch1",
                slug: "ethereum",
                range: "30d",
                summary: "Price",
                series: [%{"label" => "price_usd", "points" => [%{"t" => 1, "v" => 2}]}]
              }
            }
          ])
        )

      assert html =~ "LightweightChart"
      assert html =~ "price_usd"
    end

    test "renders a skill invocation" do
      html = render_turn(turn([%{activity: %{kind: :skill, name: "crypto-research"}}]))

      assert html =~ "crypto-research"
    end

    test "renders clarification questions instead of a report" do
      turn =
        turn(
          [%{activity: %{kind: :clarification, questions: ["Which timeframe?"]}}],
          %{phase: :awaiting_user}
        )

      assert render_turn(turn) =~ "Which timeframe?"
    end

    test "renders the report markdown as sanitized html" do
      report = "## Findings\n\nETH fees fell.<script>alert(1)</script>"

      html =
        render_turn(turn([], %{report: report, phase: :completed, finished_at: @now + 5_000}))

      assert html =~ "Findings"
      assert html =~ "ETH fees fell."
      refute html =~ "<script>"
    end

    test "renders an in-report chart fence as a server-side svg" do
      report = """
      ## Sources of chatter

      ```chart
      {"type": "pie", "title": "Messages by source", "slices": [{"label": "Twitter", "value": 70}, {"label": "Reddit", "value": 30}]}
      ```
      """

      html = render_turn(turn([], %{report: report, phase: :completed, finished_at: @now}))

      assert html =~ "Messages by source"
      assert html =~ "Twitter"
      assert html =~ "70%"
      assert html =~ "<svg"
      # The fence is consumed, not printed as a code block. (The raw markdown does
      # still appear once, in the copy button's data-copy payload — by design.)
      refute html =~ "<pre"
      refute html =~ "<code"
    end

    test "renders the error of a failed turn" do
      turn = turn([], %{phase: :failed, error: "Agent budget exhausted", finished_at: @now})
      html = render_turn(turn)

      assert html =~ "Agent budget exhausted"
      assert html =~ "bg-error/5"
    end

    test "a failed turn says how long it ran, even with nothing else to show" do
      turn = turn([], %{phase: :failed, error: "boom", finished_at: @now + 65_000})
      html = render_turn(turn)

      assert html =~ "Failed after 1m 05s"
      assert html =~ "boom"
    end

    test "a settled turn quotes the agent's own run clock and ledger once reported" do
      usage = %{
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

      turn =
        turn([%{activity: %{kind: :search_query, id: "s1", query: "q"}}, usage], %{
          phase: :completed,
          report: "ok",
          finished_at: @now + 300_000
        })

      html = render_turn(turn)

      # The agent's 4m 12s, not the wall clock's 5m 00s — it matches the agent's own text.
      assert html =~ "Researched in 4m 12s"
      refute html =~ "5m 00s"
      assert html =~ "42 tool calls"
      assert html =~ "380k tokens"
      assert html =~ "3 sub-agent runs"
      assert html =~ "$0.12"
    end

    test "a failed turn uses the ledger too; a running one still counts the wall clock" do
      usage = %{activity: %{kind: :usage, elapsed_s: 30.0, tool_calls: 2}}

      failed = turn([usage], %{phase: :failed, error: "x", finished_at: @now + 90_000})
      assert render_turn(failed) =~ "Failed after 30s"

      running = turn([%{thinking: %{id: "m1", text: "working"}}, usage], %{phase: :researching})
      assert render_turn(running, running: true, now_ms: @now + 7_000) =~ "7s"
    end

    test "a ledger without numbers adds nothing to the footer" do
      usage = %{activity: %{kind: :usage, elapsed_s: nil, tool_calls: 0, cost_usd: 0.0}}

      turn =
        turn([%{activity: %{kind: :search_query, id: "s1", query: "q"}}, usage], %{
          phase: :completed,
          report: "ok",
          finished_at: @now + 12_000
        })

      html = render_turn(turn)

      assert html =~ "Researched in 12s"
      refute html =~ "tool call"
      refute html =~ "$"
    end

    test "a page read renders as its own row with a domain link and the output" do
      turn =
        turn(
          [
            %{activity: %{kind: :fetch_call, id: "f1", url: "https://example.com/report"}},
            %{activity: %{kind: :fetch_result, id: "f1", ok: true, summary: "Fetched 12k chars"}}
          ],
          %{phase: :completed, finished_at: @now}
        )

      html = render_turn(turn)

      assert html =~ "Read page"
      assert html =~ ~s(href="https://example.com/report")
      assert html =~ "example.com"
      assert html =~ "Fetched 12k chars"
      assert html =~ "1 page read"
      refute html =~ "web_fetch"
    end

    test "agent status rows read as sentences" do
      turn =
        turn(
          [
            %{activity: %{kind: :status, state: "loop_detected", detail: nil, repeats: 3}},
            %{
              activity: %{kind: :status, state: "budget_soft", detail: nil, reason: "tool_calls"}
            },
            %{
              activity: %{
                kind: :status,
                state: "revising",
                detail: "2 uncited sources",
                reason: "report_quality"
              }
            },
            %{activity: %{kind: :status, state: "loop_halt", detail: nil, repeats: 4}},
            %{
              activity: %{
                kind: :status,
                state: "runaway_output",
                detail: "the model kept repeating 'BTC#'"
              }
            },
            %{activity: %{kind: :status, state: "runaway_halt", detail: nil}},
            %{
              activity: %{
                kind: :status,
                state: "sandbox_reset",
                detail: "No such container: llmsbx_abc"
              }
            }
          ],
          %{phase: :completed, report: "ok", finished_at: @now}
        )

      html = render_turn(turn)

      assert html =~ "Noticed the same tool call repeating (3×)"

      assert html =~
               "Cut off runaway output (the model kept repeating &#39;BTC#&#39;) — nudged the agent to continue"

      assert html =~ "Stopped: runaway output again (the model repeated itself)"

      assert html =~
               "Sandbox session was lost mid-run (No such container: llmsbx_abc) — opened a fresh one; files written earlier are gone"

      assert html =~ "Approaching the run budget for tool calls"
      assert html =~ "Revising the report: 2 uncited sources"
      assert html =~ "kept repeating the same tool call (4×)"
      assert html =~ "text-warning"
      assert html =~ "· status"
    end

    test "compaction is its own element: running, done, or interrupted when the turn died" do
      compacting = %{
        activity: %{kind: :status, state: "compacting", detail: nil, tokens_estimate: 120_000}
      }

      compacted = %{
        activity: %{
          kind: :status,
          state: "compacted",
          detail: nil,
          tokens_estimate: 120_000,
          messages_summarized: 40
        }
      }

      running = render_turn(turn([compacting]), running: true, now_ms: @now)
      assert running =~ "Compacting context"
      assert running =~ "working context near 120k tokens"
      assert running =~ "loading-spinner"
      refute running =~ "· status"

      done = render_turn(turn([compacting, compacted], %{phase: :completed, finished_at: @now}))
      assert done =~ "Compacted context"

      assert done =~
               "summarized 40 earlier messages (~120k tokens) into a shorter working context"

      refute done =~ "Compacting context"

      died = render_turn(turn([compacting], %{phase: :failed, error: "boom", finished_at: @now}))
      assert died =~ "Compaction interrupted"
      refute died =~ "loading-spinner"
    end

    test "a finished call shows the shape of its arguments, never a long value" do
      html =
        render_turn(
          turn([
            %{
              activity: %{
                kind: :mcp_call,
                id: "c1",
                tool: "write_file",
                args: %{
                  "file_path" => "/notes/btc.md",
                  "content" => String.duplicate("buy the dip ", 20)
                }
              }
            }
          ])
        )

      assert html =~ "file_path=/notes/btc.md"
      assert html =~ "[240 chars]"
      refute html =~ "buy the dip"
    end

    test "why a paused turn stopped reads as a warning — it is still resumable" do
      turn =
        turn([], %{
          phase: :paused,
          error: "Connection to the research agent failed: the request timed out",
          finished_at: @now
        })

      html = render_turn(turn)

      assert html =~ "the request timed out"
      assert html =~ "bg-warning/5"
      refute html =~ "bg-error/5"
    end

    test "a finished turn needs no wall clock — it renders with now_ms nil" do
      # This is what keeps completed turns out of the per-second re-render.
      turn =
        turn([%{thinking: %{id: "m1", text: "done"}}], %{
          phase: :completed,
          report: "ok",
          finished_at: @now + 12_000
        })

      html = render_turn(turn, now_ms: nil)

      assert html =~ "12s"
    end

    test "a running turn counts elapsed time from the passed wall clock" do
      turn = turn([%{thinking: %{id: "m1", text: "working"}}], %{phase: :researching})

      html = render_turn(turn, running: true, now_ms: @now + 7_000)

      assert html =~ "7s"
    end
  end
end
