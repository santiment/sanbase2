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

    test "leaves a section after Sources untouched" do
      md =
        "## Sources\n[1] A https://a.com [2] B https://b.com\n\n" <>
          "## Appendix\nFollow-up on [1] and [2] with more detail.\n"

      out = Timeline.reflow_sources(md)
      assert out =~ "- [1] A https://a.com"
      assert out =~ "- [2] B https://b.com"
      # The later section keeps its heading and prose — not folded into bullets.
      assert out =~ "## Appendix\nFollow-up on [1] and [2] with more detail.\n"
    end
  end

  describe "split_charts" do
    test "lifts a fenced chart block out as a parsed pie spec, keeping surrounding md" do
      md =
        "Intro paragraph.\n\n" <>
          "```chart\n{\"type\":\"pie\",\"title\":\"By source\",\"slices\":[{\"label\":\"telegram\",\"value\":40},{\"label\":\"reddit\",\"value\":30}]}\n```\n\n" <>
          "Closing paragraph."

      assert [
               {:md, "Intro paragraph.\n\n"},
               {:chart, %{type: "pie", title: "By source", slices: slices}},
               {:md, "\n\nClosing paragraph."}
             ] = Timeline.split_charts(md)

      assert slices == [%{label: "telegram", value: 40}, %{label: "reddit", value: 30}]
    end

    test "accepts data/count aliases and drops non-positive slices" do
      md =
        "```chart\n{\"data\":[{\"name\":\"twitter\",\"count\":12},{\"label\":\"x\",\"value\":0}]}\n```"

      assert [{:chart, %{slices: [%{label: "twitter", value: 12}]}}] = Timeline.split_charts(md)
    end

    test "a malformed chart block stays as markdown (degrades to a code block)" do
      md = "```chart\n{not valid json}\n```"
      assert [{:md, ^md}] = Timeline.split_charts(md)
    end

    test "no fence -> a single md segment" do
      assert [{:md, "plain report"}] = Timeline.split_charts("plain report")
    end

    test "parses a line spec with series points and a spike window" do
      md =
        "```chart\n{\"type\":\"line\",\"title\":\"Vol\",\"series\":[{\"label\":\"v\",\"points\":[{\"t\":1,\"v\":10},{\"t\":2,\"v\":80}]}],\"spike\":{\"from\":1,\"to\":2}}\n```"

      assert [
               {:chart,
                %{
                  type: "line",
                  title: "Vol",
                  series: [%{label: "v", points: [%{t: 1, v: 10}, %{t: 2, v: 80}]}],
                  spike: %{from: 1, to: 2}
                }}
             ] = Timeline.split_charts(md)
    end

    test "accepts a flat points array (single series) with time/value aliases" do
      md =
        "```chart\n{\"type\":\"spike\",\"metric\":\"social_volume\",\"points\":[{\"time\":1,\"value\":5},{\"time\":2,\"value\":9}]}\n```"

      assert [{:chart, %{type: "line", series: [%{label: "social_volume", points: pts}]}}] =
               Timeline.split_charts(md)

      assert pts == [%{t: 1, v: 5}, %{t: 2, v: 9}]
    end

    test "a line spec with fewer than two points stays markdown" do
      md = "```chart\n{\"type\":\"line\",\"points\":[{\"t\":1,\"v\":5}]}\n```"
      assert [{:md, ^md}] = Timeline.split_charts(md)
    end
  end
end
