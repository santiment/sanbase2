defmodule Sanbase.Knowledge.AcademyMarkdownTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.AcademyMarkdown

  describe "clean/1" do
    test "strips frontmatter, including YAML comments that look like headings" do
      markdown = """
      ---
      title: Social Dominance
      # REF metrics-hub/metricshub/social_dominance.py
      author: Santiment Team
      ---

      ## Definition

      Social dominance compares mentions.
      """

      cleaned = AcademyMarkdown.clean(markdown)

      refute cleaned =~ "title:"
      refute cleaned =~ "REF metrics-hub"
      assert cleaned =~ "## Definition"
      assert cleaned =~ "Social dominance compares mentions."
    end

    test "removes MDX imports, media embeds and image markdown" do
      markdown = """
      import instructionVideo from './video.mp4';
      import { Notebox } from '@components';

      ## Usage Guide

      The MVRV ratio allows traders to gauge profitability.

      <iframe
        title="Santiment Chart"
        src="https://embed.santiment.net/chart?ps=bitcoin&wm=price_usd%3Bmvrv_usd_30d"
      ></iframe>

      <video src={instructionVideo} controls />

      ![Sanbase chart](./Sanbase.png)

      [![YouTube](./thumb.png)](https://youtube.com/watch?v=1)
      """

      cleaned = AcademyMarkdown.clean(markdown)

      refute cleaned =~ "import"
      refute cleaned =~ "iframe"
      refute cleaned =~ "embed.santiment.net"
      refute cleaned =~ "video"
      refute cleaned =~ "Sanbase.png"
      refute cleaned =~ "youtube.com"
      assert cleaned =~ "The MVRV ratio allows traders to gauge profitability."
      refute AcademyMarkdown.markup_residue?(cleaned)
    end

    test "keeps the inner text of JSX wrapper components and html tags" do
      markdown = """
      <Notebox type="info">
      Timebound metrics exclude inactive addresses.
      </Notebox>

      ##### SAN_ACTIVE_ADDRESSES(projectSlug, from, to) ⇒ <code>Array</code>
      """

      cleaned = AcademyMarkdown.clean(markdown)

      refute cleaned =~ "Notebox"
      refute cleaned =~ "<code>"
      assert cleaned =~ "Timebound metrics exclude inactive addresses."
      assert cleaned =~ "SAN_ACTIVE_ADDRESSES(projectSlug, from, to) ⇒ Array"
    end

    test "leaves fenced code and inline code untouched" do
      markdown = """
      Use `<metric>` as a placeholder.

      ```graphql
      # this is a comment, not a heading
      {
        getMetric(metric: "mvrv_usd") { timeseriesDataJson }
      }
      ```

      <img src="x.png" />
      """

      cleaned = AcademyMarkdown.clean(markdown)

      assert cleaned =~ "`<metric>`"
      assert cleaned =~ "# this is a comment, not a heading"
      assert cleaned =~ ~s|getMetric(metric: "mvrv_usd")|
      refute cleaned =~ "<img"
    end

    test "reduces very long links to their text and compacts table padding" do
      long_url = "https://api.santiment.net/graphiql?query=" <> String.duplicate("%7B", 100)

      markdown = """
      Try it in [GraphiQL](#{long_url}) or read [the docs](/sanapi/).

      | Plan       | Calls          |
      | ---------- | -------------- |
      | Max        | 80,000         |
      """

      cleaned = AcademyMarkdown.clean(markdown)

      assert cleaned =~ "Try it in GraphiQL or read [the docs](/sanapi/)."
      assert cleaned =~ "| Plan | Calls |"
      assert cleaned =~ "| --- | --- |"
      assert cleaned =~ "| Max | 80,000 |"
    end
  end

  describe "chunk/2" do
    test "one chunk per section with clean heading and breadcrumb" do
      markdown = """
      # MVRV

      ## Definition

      #{String.duplicate("MVRV compares market value to realized value. ", 10)}

      ## Usage Guide

      ### High MVRV Values ( > 2 )

      #{String.duplicate("MVRV of 2 means holders would double their money. ", 10)}
      """

      chunks = AcademyMarkdown.chunk(markdown, min_chunk_chars: 100)

      assert Enum.map(chunks, & &1.heading) == ["MVRV", "Usage Guide"]

      [definition, usage] = chunks
      assert definition.content =~ "## Definition"
      assert definition.breadcrumb == ["MVRV"]
      assert usage.content =~ "### High MVRV Values ( > 2 )"
      assert usage.breadcrumb == ["MVRV", "Usage Guide"]
    end

    test "by default merges sections until a chunk has at least 800 characters" do
      section = fn title -> "## #{title}\n\n" <> String.duplicate("Some metric text. ", 20) end
      markdown = Enum.map_join(["A", "B", "C", "D", "E", "F", "G"], "\n\n", section)

      chunks = AcademyMarkdown.chunk(markdown)

      assert Enum.map(chunks, & &1.heading) == ["A", "D"]
      assert Enum.all?(chunks, &(String.length(&1.content) <= 2000))
    end

    test "merges heading-only stubs into the following section" do
      markdown = """
      ## SAN_ACTIVE_ADDRESSES

      ##### SAN_ACTIVE_ADDRESSES(projectSlug, from, to, interval) ⇒ <code>Array</code>

      Returns the active addresses for the specified asset.

      ## SAN_MVRV_RATIO

      ##### SAN_MVRV_RATIO(projectSlug, from, to) ⇒ <code>Array</code>

      Returns the MVRV ratio for the specified asset.
      """

      chunks = AcademyMarkdown.chunk(markdown, min_chunk_chars: 100)

      assert Enum.map(chunks, & &1.heading) == ["SAN_ACTIVE_ADDRESSES", "SAN_MVRV_RATIO"]
      assert Enum.all?(chunks, &(String.length(&1.content) > 60))
      assert hd(chunks).content =~ "Returns the active addresses"
    end

    test "a page that is only frontmatter and components yields no chunks" do
      markdown = """
      ---
      title: Assets changelog
      ---

      import AssetsChangelog from '$components/features/changelog/Assets.astro'

      <AssetsChangelog />
      """

      assert AcademyMarkdown.chunk(markdown) == []
      assert Sanbase.Knowledge.Academy.preview_chunks(markdown, "Assets changelog") == []
    end

    test "strips link syntax from headings" do
      markdown = """
      ## [MVRV Ratio](/metrics/mvrv)

      #{String.duplicate("The MVRV ratio is a valuation metric. ", 10)}
      """

      assert [%{heading: "MVRV Ratio"}] = AcademyMarkdown.chunk(markdown)
    end

    test "ignores # lines inside code fences when splitting sections" do
      markdown = """
      ## Example

      ```python
      # fetch data
      import san
      san.get("daily_active_addresses/bitcoin")
      ```

      #{String.duplicate("The example fetches daily active addresses. ", 10)}
      """

      assert [%{heading: "Example", content: content}] = AcademyMarkdown.chunk(markdown)
      assert content =~ "# fetch data"
      assert content =~ "import san"
    end

    test "a fence line with an info string does not close an open fence" do
      markdown = """
      ## Example

      ```text
      ```python
      # not a heading
      ```

      The example shows a fence line with an info string inside a block.
      """

      assert [%{heading: "Example", content: content}] =
               AcademyMarkdown.chunk(markdown, min_chunk_chars: 1)

      assert content =~ "# not a heading"
    end

    test "splits oversized sections and keeps the heading on every piece" do
      paragraph = String.duplicate("word ", 150)
      markdown = "## Long Section\n\n" <> Enum.map_join(1..6, "\n\n", fn _ -> paragraph end)

      chunks = AcademyMarkdown.chunk(markdown, chunk_size: 1000, chunk_overlap: 100)

      assert length(chunks) > 1
      assert Enum.all?(chunks, &(&1.heading == "Long Section"))
      assert Enum.all?(chunks, &(String.length(&1.content) <= 1000))
    end
  end

  describe "clean_heading/1" do
    test "removes emphasis and code markers but keeps snake_case names" do
      assert AcademyMarkdown.clean_heading("**Bold** and _italic_ `code`") ==
               "Bold and italic code"

      assert AcademyMarkdown.clean_heading("SAN_MVRV_LONG_SHORT_DIFF") ==
               "SAN_MVRV_LONG_SHORT_DIFF"

      assert AcademyMarkdown.clean_heading("`mvrv_usd_365d` {#mvrv-365}") == "mvrv_usd_365d"
    end
  end

  describe "embedding_text/2" do
    test "prepends title and breadcrumb, deduplicating the title" do
      chunk = %{content: "body", breadcrumb: ["MVRV", "Usage Guide"]}

      assert AcademyMarkdown.embedding_text("MVRV", chunk) == "MVRV > Usage Guide\n\nbody"
    end

    test "returns the bare content when there is no title or breadcrumb" do
      assert AcademyMarkdown.embedding_text(nil, %{content: "body", breadcrumb: []}) == "body"
    end
  end
end
