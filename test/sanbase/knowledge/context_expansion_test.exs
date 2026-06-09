defmodule Sanbase.Knowledge.ContextExpansionTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.ContextExpansion

  # These cover the branches that must hold without ever touching the database:
  # the stitching of fetched neighbours is exercised by Unchunker's own tests.

  describe "expand/3 passthrough guarantees" do
    test "empty hit list returns empty list for any source" do
      assert ContextExpansion.expand([], :insight) == []
      assert ContextExpansion.expand([], :academy) == []
    end

    test "unknown source returns hits unchanged" do
      hits = [%{post_id: 1, chunk_index: 0, text_chunk: "x"}]
      assert ContextExpansion.expand(hits, :faq) == hits
    end

    test "insight hit without an integer chunk_index is left untouched (legacy rows)" do
      hit = %{post_id: 1, chunk_index: nil, text_chunk: "wrapped body"}
      assert ContextExpansion.expand([hit], :insight) == [hit]
    end

    test "insight hit missing chunk_index key is left untouched" do
      hit = %{post_id: 1, text_chunk: "wrapped body"}
      assert ContextExpansion.expand([hit], :insight) == [hit]
    end

    test "academy hit without an integer chunk_index is left untouched" do
      hit = %{article_id: 1, chunk_index: nil, chunk: "content"}
      assert ContextExpansion.expand([hit], :academy) == [hit]
    end

    test "academy hit missing article_id is left untouched" do
      hit = %{chunk_index: 0, chunk: "content"}
      assert ContextExpansion.expand([hit], :academy) == [hit]
    end
  end
end
