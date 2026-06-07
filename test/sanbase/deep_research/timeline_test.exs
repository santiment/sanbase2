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

  describe "reflow_sources" do
    test "re-bullets a crammed single-paragraph Sources section" do
      md =
        "Body text.\n\n## Sources\n[1] A https://a.com [2] B https://b.com [3] C https://c.com\n"

      out = Timeline.reflow_sources(md)
      assert out =~ "- [1] A https://a.com"
      assert out =~ "- [2] B https://b.com"
      assert out =~ "- [3] C https://c.com"
    end

    test "is a no-op when already one-per-line" do
      md = "## Sources\n- [1] A\n- [2] B\n"
      assert Timeline.reflow_sources(md) == md
    end

    test "is a no-op without a Sources heading" do
      md = "Just a report with [1] and [2] inline."
      assert Timeline.reflow_sources(md) == md
    end
  end
end
