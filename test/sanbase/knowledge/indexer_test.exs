defmodule Sanbase.Knowledge.IndexerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Indexer

  describe "sources/0" do
    test "lists the known sources" do
      assert Indexer.sources() == [:faq, :insight, :academy]
    end
  end

  describe "reindex/2 validation" do
    test "raises on an unknown source" do
      assert_raise ArgumentError, ~r/unknown source/, fn ->
        Indexer.reindex(:bogus)
      end
    end

    test "raises listing every unknown source in a list" do
      assert_raise ArgumentError, ~r/articles.*posts|posts.*articles/, fn ->
        Indexer.reindex([:faq, :articles, :posts])
      end
    end

    test "an empty source list does no work and returns an empty map" do
      assert Indexer.reindex([]) == %{}
    end
  end
end
