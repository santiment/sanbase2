defmodule Sanbase.Knowledge.ContextTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Context

  describe "assemble/2" do
    test "empty hits give empty string for every source" do
      assert Context.assemble([], :faq) == ""
      assert Context.assemble([], :insight) == ""
      assert Context.assemble([], :academy) == ""
    end

    test "academy entry carries source marker, link and chunk text" do
      hits = [
        %{title: "MVRV", url: "https://academy.santiment.net/mvrv", chunk: "MVRV body text"}
      ]

      text = Context.assemble(hits, :academy)

      assert text =~ "Source marker: [Academy] [MVRV](https://academy.santiment.net/mvrv)"
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

      assert text =~ "Source marker: [FAQ] [What is MVRV?](http"
      refute text =~ "[FAQ #"
      assert text =~ "/admin/faq/550e8400-e29b-41d4-a716-446655440000)"
    end

    test "faq label truncates a long question to ~100 chars with an ellipsis" do
      long = String.duplicate("a", 150)
      hits = [%{id: "1", question: long, answer_markdown: "x"}]

      text = Context.assemble(hits, :faq)

      assert text =~ "[FAQ] [#{String.duplicate("a", 100)}…]("
      refute text =~ "[#{String.duplicate("a", 101)}"
    end
  end
end
