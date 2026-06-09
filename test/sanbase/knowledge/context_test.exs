defmodule Sanbase.Knowledge.ContextTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Context

  describe "marker/2" do
    test "faq marker carries the question label and the admin faq url" do
      hit = %{id: "550e8400-e29b-41d4-a716-446655440000", question: "What is MVRV?"}

      marker = Context.marker(hit, :faq)

      assert marker.source == :faq
      assert marker.prefix == "FAQ"
      assert marker.label == "What is MVRV?"
      assert marker.url =~ "/admin/faq/550e8400-e29b-41d4-a716-446655440000"
    end

    test "faq label folds whitespace and truncates a long question to ~100 chars" do
      long = String.duplicate("a", 150)

      assert Context.marker(%{id: "1", question: long}, :faq).label ==
               String.duplicate("a", 100) <> "…"

      assert Context.marker(%{id: "1", question: "a\n  b\tc"}, :faq).label == "a b c"
    end

    test "insight marker carries the post title and an insight url" do
      marker = Context.marker(%{post_id: 42, post_title: "Time to buy Bitcoin?"}, :insight)

      assert marker.source == :insight
      assert marker.prefix == "Insight"
      assert marker.label == "Time to buy Bitcoin?"
      assert marker.url =~ "http"
    end

    test "academy marker passes the article title and url through" do
      marker =
        Context.marker(%{title: "MVRV", url: "https://academy.santiment.net/mvrv"}, :academy)

      assert marker == %{
               source: :academy,
               prefix: "Academy",
               label: "MVRV",
               url: "https://academy.santiment.net/mvrv"
             }
    end
  end

  describe "assemble/2" do
    test "empty hits give empty string for every source" do
      assert Context.assemble([], :faq) == ""
      assert Context.assemble([], :insight) == ""
      assert Context.assemble([], :academy) == ""
    end

    test "faq block leads with the numbered source header and carries Q/A" do
      hits = [
        %{marker_id: 2, id: "abc", question: "What is MVRV?", answer_markdown: "MV / RV."}
      ]

      text = Context.assemble(hits, :faq)

      assert text =~ "Source [2] — FAQ: What is MVRV?"
      assert text =~ "Question: What is MVRV?"
      assert text =~ "Answer: MV / RV."
    end

    test "insight block carries the numbered header, the publish date and the chunk text" do
      hits = [
        %{
          marker_id: 1,
          post_id: 42,
          post_title: "Time to buy Bitcoin?",
          published_at: ~N[2021-05-12 09:30:00],
          text_chunk: "Look for an entry near 36,600."
        }
      ]

      text = Context.assemble(hits, :insight)

      assert text =~ "Source [1] — Insight: Time to buy Bitcoin?"
      assert text =~ "Published: 2021-05-12"
      assert text =~ "Look for an entry near 36,600."
    end

    test "academy block carries the numbered header and the chunk text" do
      hits = [
        %{
          marker_id: 3,
          title: "MVRV",
          url: "https://academy.santiment.net/mvrv",
          chunk: "MVRV body text"
        }
      ]

      text = Context.assemble(hits, :academy)

      assert text =~ "Source [3] — Academy: MVRV"
      assert text =~ "Most relevant chunk from article: MVRV body text"
    end

    test "the source header omits the id when a hit carries no marker_id (eval path)" do
      hits = [%{id: "abc", question: "What is MVRV?", answer_markdown: "MV / RV."}]

      text = Context.assemble(hits, :faq)

      assert text =~ "Source — FAQ: What is MVRV?"
      refute text =~ "Source ["
    end

    test "no URL is embedded in the prompt context — only the model-cited id is" do
      hits = [
        %{marker_id: 3, title: "MVRV", url: "https://academy.santiment.net/mvrv", chunk: "body"}
      ]

      refute Context.assemble(hits, :academy) =~ "https://academy.santiment.net/mvrv"
    end

    test "insight publish line includes the age so the model need not compute it" do
      pub = Date.add(Date.utc_today(), -3)
      hits = [%{marker_id: 1, post_id: 7, post_title: "T", published_at: pub, text_chunk: "body"}]

      assert Context.assemble(hits, :insight) =~ "Published: #{Date.to_iso8601(pub)} (3 days ago)"
    end

    test "insight published today reads as today, not '0 days ago'" do
      hits = [
        %{
          marker_id: 1,
          post_id: 8,
          post_title: "T",
          published_at: Date.utc_today(),
          text_chunk: "b"
        }
      ]

      assert Context.assemble(hits, :insight) =~ "(today)"
    end

    test "insight publish date degrades to a label when missing" do
      hits = [%{marker_id: 1, post_id: 1, post_title: "T", text_chunk: "body"}]

      assert Context.assemble(hits, :insight) =~ "Published: unknown date"
    end
  end

  describe "escape_label/1" do
    # Labels are user-controlled (post/article titles, FAQ questions). When the
    # label is interpolated into a `[label](url)` citation link, a crafted title
    # with markdown link delimiters must not be able to close the label early and
    # inject a different (e.g. phishing) target. escape_label neutralises them.
    test "escapes the markdown link delimiters and the backslash" do
      assert Context.escape_label("a]b") == "a\\]b"
      assert Context.escape_label("a[b") == "a\\[b"
      assert Context.escape_label("a(b)") == "a\\(b\\)"
      # backslash is escaped first so the others are not double-escaped
      assert Context.escape_label("a\\b") == "a\\\\b"
    end

    test "an escaped malicious title cannot break out of a citation link" do
      label = "Click here](https://phishing.example) and [more"
      escaped = Context.escape_label(label)

      html = Earmark.as_html!("[#{escaped}](https://academy.santiment.net/mvrv)")

      assert html =~ ~s(href="https://academy.santiment.net/mvrv")
      refute html =~ ~s(href="https://phishing.example")
      assert length(Regex.scan(~r/<a /, html)) == 1
    end
  end
end
