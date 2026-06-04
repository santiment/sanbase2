defmodule Sanbase.Knowledge.ContextTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Context

  describe "assemble/2" do
    test "empty hits give empty string for every source" do
      assert Context.assemble([], :faq) == ""
      assert Context.assemble([], :insight) == ""
      assert Context.assemble([], :academy) == ""
    end

    test "insight entry carries source marker, the publish date, and the chunk text" do
      hits = [
        %{
          post_id: 42,
          post_title: "Time to buy Bitcoin?",
          published_at: ~N[2021-05-12 09:30:00],
          text_chunk: "Look for an entry near 36,600."
        }
      ]

      text = Context.assemble(hits, :insight)

      assert text =~ "Source marker: [Insight: Time to buy Bitcoin?]("
      assert text =~ "Published: 2021-05-12"
      assert text =~ "Look for an entry near 36,600."
    end

    test "insight publish line includes the age so the model need not compute it" do
      pub = Date.add(Date.utc_today(), -3)

      hits = [
        %{post_id: 7, post_title: "T", published_at: pub, text_chunk: "body"}
      ]

      assert Context.assemble(hits, :insight) =~ "Published: #{Date.to_iso8601(pub)} (3 days ago)"
    end

    test "insight published today reads as today, not '0 days ago'" do
      hits = [
        %{post_id: 8, post_title: "T", published_at: Date.utc_today(), text_chunk: "body"}
      ]

      assert Context.assemble(hits, :insight) =~ "(today)"
    end

    test "insight publish date degrades to a label when missing" do
      hits = [%{post_id: 1, post_title: "T", text_chunk: "body"}]

      assert Context.assemble(hits, :insight) =~ "Published: unknown date"
    end

    test "academy entry carries source marker, link and chunk text" do
      hits = [
        %{title: "MVRV", url: "https://academy.santiment.net/mvrv", chunk: "MVRV body text"}
      ]

      text = Context.assemble(hits, :academy)

      assert text =~ "Source marker: [Academy: MVRV](https://academy.santiment.net/mvrv)"
      assert text =~ "Most relevant chunk from article: MVRV body text"
    end

    test "academy joins multiple chunks" do
      hits = [
        %{title: "A", url: "u1", chunk: "first"},
        %{title: "B", url: "u2", chunk: "second"}
      ]

      text = Context.assemble(hits, :academy)

      assert text =~ "first"
      assert text =~ "second"
    end

    test "faq link label is the question, not the id" do
      hits = [
        %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          question: "What is MVRV?",
          answer_markdown: "MV / RV."
        }
      ]

      text = Context.assemble(hits, :faq)

      assert text =~ "Source marker: [FAQ: What is MVRV?](http"
      refute text =~ "[FAQ #"
      assert text =~ "/admin/faq/550e8400-e29b-41d4-a716-446655440000)"
    end

    test "faq label truncates a long question to ~100 chars with an ellipsis" do
      long = String.duplicate("a", 150)
      hits = [%{id: "1", question: long, answer_markdown: "x"}]

      text = Context.assemble(hits, :faq)

      assert text =~ "[FAQ: #{String.duplicate("a", 100)}…]("
      refute text =~ "[#{String.duplicate("a", 101)}"
    end

    # Guards two live rendering bugs: (1) a dead `[Academy] [label]` with no link
    # (the marker must be a SINGLE markdown link), and (2) nested brackets in the
    # link text (`[[Academy] label]`) which some renderers fail to parse. The
    # source tag is joined to the label with a colon, inside one link, no brackets.
    test "marker renders as one clickable link with no nested brackets in the link text" do
      hits = [%{title: "MVRV", url: "https://academy.santiment.net/mvrv", chunk: "body"}]

      marker =
        hits
        |> Context.assemble(:academy)
        |> String.split("\n", trim: true)
        |> Enum.find(&String.starts_with?(&1, "Source marker: "))
        |> String.replace_leading("Source marker: ", "")

      html = Earmark.as_html!(marker)

      assert html =~ ~s(<a href="https://academy.santiment.net/mvrv">Academy: MVRV</a>)
      # The marker itself must not contain a bracket inside the link text.
      refute marker =~ "[Academy]"
      refute marker =~ "[["
    end
  end
end
