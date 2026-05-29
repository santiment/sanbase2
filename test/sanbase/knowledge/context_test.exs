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

      assert text =~ "Source marker: [MVRV](https://academy.santiment.net/mvrv)"
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
  end
end
