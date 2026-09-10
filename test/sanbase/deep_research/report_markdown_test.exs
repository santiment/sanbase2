defmodule Sanbase.DeepResearch.ReportMarkdownTest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.ReportMarkdown

  describe "reflow_sources" do
    test "re-bullets a crammed single-paragraph Sources section" do
      md =
        "Body text.\n\n## Sources\n[1] A https://a.com [2] B https://b.com [3] C https://c.com\n"

      out = ReportMarkdown.reflow_sources(md)
      assert out =~ "- [1] A https://a.com"
      assert out =~ "- [2] B https://b.com"
      assert out =~ "- [3] C https://c.com"
    end

    test "is a no-op when already one-per-line" do
      md = "## Sources\n- [1] A\n- [2] B\n"
      assert ReportMarkdown.reflow_sources(md) == md
    end

    test "is a no-op without a Sources heading" do
      md = "Just a report with [1] and [2] inline."
      assert ReportMarkdown.reflow_sources(md) == md
    end

    test "leaves a section after Sources untouched" do
      md =
        "## Sources\n[1] A https://a.com [2] B https://b.com\n\n" <>
          "## Appendix\nFollow-up on [1] and [2] with more detail.\n"

      out = ReportMarkdown.reflow_sources(md)
      assert out =~ "- [1] A https://a.com"
      assert out =~ "- [2] B https://b.com"
      # The later section keeps its heading and prose — not folded into bullets.
      assert out =~ "## Appendix\nFollow-up on [1] and [2] with more detail.\n"
    end

    test "is a no-op when a heading directly follows an empty Sources section" do
      md = "Intro text.\n\n## Sources\n## Conclusion\nText citing [1] and [2] again.\n"
      assert ReportMarkdown.reflow_sources(md) == md
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
             ] = ReportMarkdown.split_charts(md)

      assert slices == [%{label: "telegram", value: 40}, %{label: "reddit", value: 30}]
    end

    test "accepts data/count aliases and drops non-positive slices" do
      md =
        "```chart\n{\"data\":[{\"name\":\"twitter\",\"count\":12},{\"label\":\"x\",\"value\":0}]}\n```"

      assert [{:chart, %{slices: [%{label: "twitter", value: 12}]}}] =
               ReportMarkdown.split_charts(md)
    end

    test "a [chart:<id>] line becomes an artifact reference between markdown runs" do
      md = "Price rose 24%[1].\n\n[chart:1a2b3c4d]\n\nVolume peaked mid-August[1].\n"

      assert [
               {:md, "Price rose 24%[1].\n\n"},
               {:artifact, "1a2b3c4d"},
               {:md, "\n\nVolume peaked mid-August[1].\n"}
             ] = ReportMarkdown.split_charts(md)
    end

    test "a placeholder that is not an 8-hex id, or not alone on its line, stays markdown" do
      md = "see [chart:nope] and inline [chart:1a2b3c4d] text"
      assert [{:md, ^md}] = ReportMarkdown.split_charts(md)
    end

    test "chart_refs lists placed ids once, in order" do
      md = "[chart:1a2b3c4d]\nx\n[chart:ffffffff]\n[chart:1a2b3c4d]\n[chart:zz]"
      assert ReportMarkdown.chart_refs(md) == ["1a2b3c4d", "ffffffff"]
      assert ReportMarkdown.chart_refs(nil) == []
    end

    test "a CRLF report still places its chart" do
      # The token's line ending is consumed with the token; the prose around it survives.
      assert [{:md, "a\r\n"}, {:artifact, "1a2b3c4d"}, {:md, "\nb"}] =
               ReportMarkdown.split_charts("a\r\n[chart:1a2b3c4d]\r\nb")

      assert ReportMarkdown.chart_refs("a\r\n[chart:1a2b3c4d]\r\nb") == ["1a2b3c4d"]
    end

    test "a ref inside a code fence is text, not a placement" do
      md = "```\n[chart:1a2b3c4d]\n```"
      assert [{:md, ^md}] = ReportMarkdown.split_charts(md)
      assert ReportMarkdown.chart_refs(md <> "\n") == []
    end

    test "a ref inside a tilde fence is text, not a placement" do
      md = "~~~\n[chart:1a2b3c4d]\n~~~"
      assert [{:md, ^md}] = ReportMarkdown.split_charts(md)
      assert ReportMarkdown.chart_refs("intro\n" <> md <> "\n") == []
    end

    test "a ref that shares its line with an inline fence is not alone, so not a placement" do
      md = "see ```x``` [chart:1a2b3c4d]\n"
      refute Enum.any?(ReportMarkdown.split_charts(md), &match?({:artifact, _}, &1))
      assert ReportMarkdown.chart_refs(md) == []
    end

    test "a malformed chart block stays as markdown (degrades to a code block)" do
      md = "```chart\n{not valid json}\n```"
      assert [{:md, ^md}] = ReportMarkdown.split_charts(md)
    end

    test "no fence -> a single md segment" do
      assert [{:md, "plain report"}] = ReportMarkdown.split_charts("plain report")
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
             ] = ReportMarkdown.split_charts(md)
    end

    test "accepts a flat points array (single series) with time/value aliases" do
      md =
        "```chart\n{\"type\":\"spike\",\"metric\":\"social_volume\",\"points\":[{\"time\":1,\"value\":5},{\"time\":2,\"value\":9}]}\n```"

      assert [{:chart, %{type: "line", series: [%{label: "social_volume", points: pts}]}}] =
               ReportMarkdown.split_charts(md)

      assert pts == [%{t: 1, v: 5}, %{t: 2, v: 9}]
    end

    test "a line spec with fewer than two points stays markdown" do
      md = "```chart\n{\"type\":\"line\",\"points\":[{\"t\":1,\"v\":5}]}\n```"
      assert [{:md, ^md}] = ReportMarkdown.split_charts(md)
    end
  end
end
