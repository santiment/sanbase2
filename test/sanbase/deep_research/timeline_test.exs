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
      for phase <- [:planning, :researching, :writing] do
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

      settled = %{turn() | phase: :completed, finished_at: 10}
      assert Timeline.pause_turn(settled, 500) == settled
    end

    test "stamp_finished_at records the finish time without settling the phase" do
      stamped = Timeline.stamp_finished_at(turn(), 500)

      assert stamped.phase == :planning
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
end
