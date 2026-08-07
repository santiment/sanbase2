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
