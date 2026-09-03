defmodule Sanbase.DeepResearch.TimelineTest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.Timeline

  defp turn(), do: Timeline.new_turn("q", 1, 0)

  describe "apply_result + reduce_timeline" do
    test "search_query then search_results merge by id" do
      t =
        turn()
        |> Timeline.apply_result(%{activity: %{kind: :search_query, id: "s1", query: "yields"}})
        |> Timeline.apply_result(%{
          activity: %{
            kind: :search_results,
            id: "s1",
            query: "yields",
            count: 2,
            results: [%{title: "a", url: "https://a.com", domain: "a.com", snippet: nil}]
          }
        })

      assert [%{kind: :search, id: "s1", query: "yields", count: 2, results: [_]}] = t.timeline
    end

    test "mcp_call then mcp_result patch by id (done: true)" do
      t =
        turn()
        |> Timeline.apply_result(%{activity: %{kind: :mcp_call, id: "m1", tool: "f", args: %{}}})
        |> Timeline.apply_result(%{
          activity: %{kind: :mcp_result, id: "m1", tool: "f", ok: true, summary: "done"}
        })

      assert [%{kind: :mcp, id: "m1", ok: true, summary: "done", done: true}] = t.timeline
    end

    test "web_fetch call then result patch by id (done: true)" do
      t =
        turn()
        |> Timeline.apply_result(%{
          activity: %{kind: :fetch_call, id: "f1", url: "https://example.com/a"}
        })
        |> Timeline.apply_result(%{
          activity: %{kind: :fetch_result, id: "f1", ok: true, summary: "Fetched"}
        })

      assert [
               %{
                 kind: :fetch,
                 id: "f1",
                 url: "https://example.com/a",
                 ok: true,
                 summary: "Fetched",
                 done: true
               }
             ] = t.timeline
    end

    test "status rows keep their facts, compaction becomes its own item; transient, end and unknown states are dropped" do
      t =
        turn()
        |> Timeline.apply_result(%{
          activity: %{kind: :status, state: "compacting", detail: nil, tokens_estimate: 120_000}
        })
        |> Timeline.apply_result(%{
          activity: %{
            kind: :status,
            state: "compacted",
            detail: nil,
            tokens_estimate: 120_000,
            messages_summarized: 40
          }
        })
        |> Timeline.apply_result(%{
          activity: %{kind: :status, state: "loop_detected", detail: nil, repeats: 3}
        })
        |> Timeline.apply_result(%{
          activity: %{
            kind: :status,
            state: "subagent_start",
            detail: nil,
            role: "research-subagent"
          }
        })
        |> Timeline.apply_result(%{
          activity: %{
            kind: :status,
            state: "done",
            detail: "Report delivered.",
            reason: "report_delivered"
          }
        })
        |> Timeline.apply_result(%{activity: %{kind: :status, state: "teleporting", detail: nil}})

      assert [
               %{
                 kind: :compaction,
                 state: "compacted",
                 tokens_estimate: 120_000,
                 messages_summarized: 40
               },
               %{kind: :status, state: "loop_detected", detail: nil, repeats: 3}
             ] == t.timeline
    end

    test "compacting opens the compaction item and compacted closes it; a lone compacted still lands" do
      compacting = %{
        activity: %{kind: :status, state: "compacting", detail: nil, tokens_estimate: 120_000}
      }

      compacted = %{
        activity: %{
          kind: :status,
          state: "compacted",
          detail: nil,
          tokens_estimate: 118_000,
          messages_summarized: 40
        }
      }

      open = Timeline.apply_result(turn(), compacting)

      assert [%{kind: :compaction, state: "compacting", tokens_estimate: 120_000}] ==
               open.timeline

      closed = Timeline.apply_result(open, compacted)

      assert [
               %{
                 kind: :compaction,
                 state: "compacted",
                 tokens_estimate: 118_000,
                 messages_summarized: 40
               }
             ] == closed.timeline

      assert length(Timeline.apply_result(closed, compacted).timeline) == 2
    end

    test "a new turn is queued until the run's metadata event says a worker took it" do
      t = turn()
      assert t.phase == :queued
      assert Timeline.running_phase?(:queued)

      t =
        Timeline.apply_result(t, %{
          run_id: "r1",
          phase: :planning,
          activity: %{kind: :status, state: "run_restarted", detail: nil, attempt: 2}
        })

      assert t.phase == :planning
      assert [%{kind: :status, state: "run_restarted", detail: nil, attempt: 2}] == t.timeline
    end

    test "events stamp last_event_at; the live draft stays until real output replaces it" do
      draft = %{kind: :tool_call_draft, name: "execute", chars: 12, preview: "{\"command\":"}

      t = Timeline.apply_result(turn(), %{live: draft, at: 1_000})
      assert t.last_event_at == 1_000
      assert t.live == draft
      assert t.timeline == []

      # A bigger draft replaces the smaller one.
      t = Timeline.apply_result(t, %{live: %{draft | chars: 40}, at: 2_000})
      assert t.live.chars == 40

      # An event with nothing to say about the model's output leaves the draft alone.
      t = Timeline.apply_result(t, %{phase: :researching, at: 3_000})
      assert t.live.chars == 40
      assert t.last_event_at == 3_000

      # The call landed: its tool event clears the draft.
      t =
        Timeline.apply_result(t, %{
          activity: %{kind: :search_query, id: "s1", query: "q"},
          at: 4_000
        })

      assert t.live == nil

      # Prose after a draft clears it too; settling always does.
      t = Timeline.apply_result(t, %{live: draft})
      t = Timeline.apply_result(t, %{thinking: %{id: "m1", text: "Now"}})
      assert t.live == nil
      t = Timeline.apply_result(t, %{live: draft})
      assert Timeline.cancel_turn(t, 5_000).live == nil
    end

    test "the usage ledger is kept once, replaced by a later one, and off the rendered flow" do
      t =
        turn()
        |> Timeline.apply_result(%{activity: %{kind: :search_query, id: "s1", query: "q"}})
        |> Timeline.apply_result(%{
          activity: %{
            kind: :usage,
            elapsed_s: 10.0,
            tool_calls: 1,
            total_tokens: nil,
            cost_usd: nil
          }
        })
        |> Timeline.apply_result(%{
          activity: %{
            kind: :usage,
            elapsed_s: 25.5,
            tool_calls: 4,
            total_tokens: 900,
            cost_usd: 0.02
          }
        })

      assert Timeline.usage(t) == %{
               kind: :usage,
               elapsed_s: 25.5,
               tool_calls: 4,
               total_tokens: 900,
               cost_usd: 0.02
             }

      assert Enum.count(t.timeline, &(&1.kind == :usage)) == 1
      assert [{:tools, [%{kind: :search}], true}] = Timeline.segment(t.timeline)
      assert Timeline.usage(turn()) == nil
    end

    test "thinking snapshots replace by id (cumulative, not appended)" do
      t =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "Hel"}})
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "Hello world"}})

      assert [%{kind: :thinking, id: "m1", text: "Hello world"}] = t.timeline
    end

    test "skills dedupe by name" do
      t =
        turn()
        |> Timeline.apply_result(%{activity: %{kind: :skill, name: "defi", path: nil}})
        |> Timeline.apply_result(%{activity: %{kind: :skill, name: "defi", path: nil}})

      assert [%{kind: :skill, name: "defi"}] = t.timeline
    end

    test "charts dedupe by id (a re-emit replaces in place)" do
      chart = %{
        kind: :chart,
        id: "c1",
        slug: "bitcoin",
        range: "90d",
        summary: nil,
        series: [%{"data" => []}]
      }

      t =
        turn()
        |> Timeline.apply_result(%{activity: chart})
        |> Timeline.apply_result(%{activity: %{chart | range: "30d"}})

      assert [%{kind: :chart, id: "c1", range: "30d"}] = t.timeline
    end

    test "sources dedupe by url" do
      src = %{kind: :source, url: "https://a.com", title: "A", domain: "a.com"}

      t =
        turn()
        |> Timeline.apply_result(%{activity: src})
        |> Timeline.apply_result(%{activity: src})

      assert [%{url: "https://a.com"}] = t.sources
      assert t.timeline == []
    end

    test "clarification sets questions + awaiting_user phase" do
      t =
        Timeline.apply_result(turn(), %{
          phase: :awaiting_user,
          activity: %{kind: :clarification, questions: ["Which region?"]}
        })

      assert t.clarification == ["Which region?"]
      assert t.phase == :awaiting_user
    end

    test "report + writing phase" do
      t = Timeline.apply_result(turn(), %{report: "# R", phase: :writing})
      assert t.report == "# R"
      assert t.phase == :writing
    end

    test "error sets failed phase + message" do
      t = Timeline.apply_result(turn(), %{error: "boom"})
      assert t.phase == :failed
      assert t.error == "boom"
    end
  end

  describe "direct_answer?" do
    test "true for a plain-text answer with no report, clarification, or research" do
      t = Timeline.apply_result(turn(), %{thinking: %{id: "m1", text: "Those were my notes."}})
      assert Timeline.direct_answer?(t)
    end

    test "false when a report was delivered" do
      t =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "answer"}})
        |> Timeline.apply_result(%{report: "# R"})

      refute Timeline.direct_answer?(t)
    end

    test "false when clarification questions were asked" do
      t =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "a"}})
        |> Timeline.apply_result(%{
          activity: %{kind: :clarification, questions: ["Which region?"]}
        })

      refute Timeline.direct_answer?(t)
    end

    test "false when research ran but no report was produced (a genuine stall)" do
      mcp =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "found data"}})
        |> Timeline.apply_result(%{activity: %{kind: :mcp_call, id: "x", tool: "f", args: %{}}})

      search =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "found data"}})
        |> Timeline.apply_result(%{activity: %{kind: :search_query, id: "s1", query: "q"}})

      refute Timeline.direct_answer?(mcp)
      refute Timeline.direct_answer?(search)
    end

    test "false when a sub-agent read a web page but no report came back" do
      t =
        turn()
        |> Timeline.apply_result(%{thinking: %{id: "m1", text: "Let me check that page."}})
        |> Timeline.apply_result(%{
          activity: %{kind: :fetch_call, id: "f1", url: "https://example.com/a"}
        })

      refute Timeline.direct_answer?(t)
    end

    test "false when the turn carries no assistant text" do
      empty = turn()
      status = Timeline.apply_result(turn(), %{activity: %{kind: :status, state: "mcp_ready"}})
      blank = Timeline.apply_result(turn(), %{thinking: %{id: "m1", text: "   "}})

      refute Timeline.direct_answer?(empty)
      refute Timeline.direct_answer?(status)
      refute Timeline.direct_answer?(blank)
    end
  end

  describe "merge_phase" do
    test "advances monotonically through in-progress order" do
      assert Timeline.merge_phase(:planning, :researching) == :researching
      assert Timeline.merge_phase(:researching, :planning) == :researching
      assert Timeline.merge_phase(:queued, :planning) == :planning
      assert Timeline.merge_phase(:planning, :queued) == :planning
    end

    test "terminal phases are sticky" do
      assert Timeline.merge_phase(:failed, :completed) == :failed
      assert Timeline.merge_phase(:cancelled, :researching) == :cancelled
    end

    test "reaching terminal wins over in-progress" do
      assert Timeline.merge_phase(:researching, :completed) == :completed
    end

    test "a resumed run moves a paused turn forward again" do
      assert Timeline.merge_phase(:paused, :planning) == :planning
      assert Timeline.merge_phase(:paused, :researching) == :researching
    end
  end

  describe "phase predicates for :paused" do
    test "paused is settled and inactive, but NOT terminal (it is resumable)" do
      assert Timeline.settled_phase?(:paused)
      assert Timeline.inactive_phase?(:paused)
      refute Timeline.terminal_phase?(:paused)
    end

    test "running phases are neither settled nor inactive" do
      for phase <- [:queued, :planning, :researching, :writing] do
        refute Timeline.settled_phase?(phase)
        refute Timeline.inactive_phase?(phase)
      end
    end
  end

  describe "settling a turn" do
    test "complete_turn completes a running turn, keeps a settled phase" do
      completed = Timeline.complete_turn(turn(), 500)

      assert completed.phase == :completed
      assert completed.finished_at == 500

      awaiting = %{turn() | phase: :awaiting_user}
      assert Timeline.complete_turn(awaiting, 500).phase == :awaiting_user
    end

    test "fail_turn records the reason and keeps an earlier error" do
      failed = Timeline.fail_turn(turn(), "boom", 500)

      assert failed.phase == :failed
      assert failed.error == "boom"
      assert Timeline.fail_turn(failed, "later", 900) == failed
    end

    test "cancel_turn cancels, unless a report already arrived" do
      assert Timeline.cancel_turn(turn(), 500).phase == :cancelled
      assert Timeline.cancel_turn(%{turn() | report: "## Done"}, 500).phase == :completed
    end

    test "pause_turn parks an unfinished turn, returns a settled one as is" do
      paused = Timeline.pause_turn(turn(), 500)

      assert paused.phase == :paused
      assert paused.finished_at == 500
      assert paused.error == nil

      settled = %{turn() | phase: :completed, finished_at: 10}
      assert Timeline.pause_turn(settled, 500) == settled
    end

    test "pause_turn keeps why the turn stopped, without overwriting an earlier error" do
      paused = Timeline.pause_turn(turn(), 500, "the connection closed mid-request")

      assert paused.phase == :paused
      assert paused.error == "the connection closed mid-request"

      # A turn that already knows what went wrong keeps its own account of it.
      assert Timeline.pause_turn(%{turn() | error: "first"}, 500, "second").error == "first"
    end

    test "stamp_finished_at records the finish time without settling the phase" do
      stamped = Timeline.stamp_finished_at(turn(), 500)

      assert stamped.phase == :queued
      assert stamped.finished_at == 500
    end

    test "the first finish time wins" do
      finished = %{turn() | finished_at: 10}

      assert Timeline.complete_turn(finished, 500).finished_at == 10
      assert Timeline.cancel_turn(finished, 500).finished_at == 10
      assert Timeline.stamp_finished_at(finished, 500).finished_at == 10
    end
  end

  describe "segment" do
    test "splits narration / tools / skill into contiguous blocks" do
      items = [
        %{kind: :thinking, id: "1", text: "a"},
        %{kind: :search, id: "s1", query: "q"},
        %{kind: :mcp, id: "m1", tool: "f"},
        %{kind: :thinking, id: "2", text: "b"},
        %{kind: :skill, name: "x"}
      ]

      assert [
               {:narration, [%{id: "1"}]},
               {:tools, [%{kind: :search}, %{kind: :mcp}], true},
               {:narration, [%{id: "2"}]},
               {:skill, [%{name: "x"}]}
             ] = Timeline.segment(items)
    end

    test "tools block running flag is false once all complete" do
      items = [
        %{kind: :search, id: "s1", query: "q", count: 3, results: []},
        %{kind: :mcp, id: "m1", tool: "f", done: true}
      ]

      assert [{:tools, _, false}] = Timeline.segment(items)
    end

    test "an unfinished page read keeps the tools block running" do
      assert [{:tools, _, true}] =
               Timeline.segment([%{kind: :fetch, id: "f1", url: "https://x.y"}])

      assert [{:tools, _, false}] =
               Timeline.segment([
                 %{kind: :fetch, id: "f1", url: "https://x.y", done: true, ok: true}
               ])
    end

    test "charts form their own always-visible block after the tools run" do
      items = [
        %{kind: :mcp, id: "m1", tool: "show_chart", done: true},
        %{kind: :chart, id: "c1", slug: "bitcoin", range: "90d", series: [%{"data" => []}]}
      ]

      assert [
               {:tools, [%{kind: :mcp}], false},
               {:chart, [%{kind: :chart, id: "c1"}]}
             ] = Timeline.segment(items)
    end
  end

  describe "coalesce" do
    test "consecutive mcp items become one group, preserving interleaving" do
      items = [
        %{kind: :search, id: "s1"},
        %{kind: :mcp, id: "m1"},
        %{kind: :mcp, id: "m2"},
        %{kind: :status, state: "mcp_ready"}
      ]

      assert [
               %{kind: :search},
               {:mcp_group, [%{id: "m1"}, %{id: "m2"}]},
               %{kind: :status}
             ] = Timeline.coalesce(items)
    end
  end

  describe "plan items" do
    test "a plan is appended once and later versions replace it in place" do
      t = Timeline.apply_result(turn(), %{thinking: %{id: "m1", text: "Planning"}})

      t =
        Timeline.apply_result(t, %{
          activity: %{kind: :plan, todos: [%{content: "a", status: "pending"}]}
        })

      t = Timeline.apply_result(t, %{thinking: %{id: "m2", text: "Working"}})

      t =
        Timeline.apply_result(t, %{
          activity: %{kind: :plan, todos: [%{content: "a", status: "completed"}]}
        })

      assert [
               %{kind: :thinking},
               %{kind: :plan, todos: [%{status: "completed"}]},
               %{kind: :thinking}
             ] =
               t.timeline

      assert [{:narration, _}, {:plan, [%{kind: :plan}]}, {:narration, _}] =
               Timeline.segment(t.timeline)
    end

    test "a plan activity clears the live draft" do
      draft = %{kind: :tool_call_draft, name: "write_todos", chars: 10, preview: "{"}
      t = Timeline.apply_result(turn(), %{live: draft})
      t = Timeline.apply_result(t, %{activity: %{kind: :plan, todos: []}})
      assert t.live == nil
    end
  end
end
