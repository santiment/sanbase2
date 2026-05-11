defmodule Sanbase.Utils.TransformTest do
  use ExUnit.Case, async: true

  alias Sanbase.Utils.Transform

  doctest Sanbase.Utils.Transform

  describe "maybe_unwrap_ok_value/1" do
    test "unwraps single-element list" do
      assert Transform.maybe_unwrap_ok_value({:ok, [42]}) == {:ok, 42}
    end

    test "returns nil for empty list" do
      assert Transform.maybe_unwrap_ok_value({:ok, []}) == {:ok, nil}
    end

    test "passes through error" do
      assert Transform.maybe_unwrap_ok_value({:error, "bad"}) == {:error, "bad"}
    end

    test "raises on non-list value" do
      assert_raise RuntimeError, fn ->
        Transform.maybe_unwrap_ok_value({:ok, 5})
      end
    end
  end

  describe "maybe_sort/3" do
    test "sorts by datetime descending" do
      data = [
        %{datetime: ~U[2024-01-01 00:00:00Z], v: 1},
        %{datetime: ~U[2024-01-03 00:00:00Z], v: 3},
        %{datetime: ~U[2024-01-02 00:00:00Z], v: 2}
      ]

      {:ok, result} = Transform.maybe_sort({:ok, data}, :datetime, :desc)
      assert Enum.map(result, & &1.v) == [3, 2, 1]
    end

    test "sorts by arbitrary key ascending" do
      data = [%{score: 5}, %{score: 1}, %{score: 3}]
      {:ok, result} = Transform.maybe_sort({:ok, data}, :score, :asc)
      assert Enum.map(result, & &1.score) == [1, 3, 5]
    end

    test "passes through errors" do
      assert Transform.maybe_sort({:error, "err"}, :datetime, :asc) == {:error, "err"}
    end
  end

  describe "maybe_fill_gaps_last_seen/3" do
    test "fills gaps with custom unknown_previous_value" do
      data = [
        %{val: nil, has_changed: 0, datetime: 1},
        %{val: 10, has_changed: 1, datetime: 2}
      ]

      assert Transform.maybe_fill_gaps_last_seen({:ok, data}, :val, 99) ==
               {:ok, [%{val: 99, datetime: 1}, %{val: 10, datetime: 2}]}
    end

    test "passes through errors" do
      assert Transform.maybe_fill_gaps_last_seen({:error, "err"}, :val) == {:error, "err"}
    end
  end

  describe "opts_to_limit_offset/1" do
    test "calculates limit and offset from page and page_size" do
      assert Transform.opts_to_limit_offset(page: 3, page_size: 20) == {20, 40}
    end

    test "defaults to page 1 and page_size 10" do
      assert Transform.opts_to_limit_offset([]) == {10, 0}
    end

    test "first page has offset 0" do
      assert Transform.opts_to_limit_offset(page: 1, page_size: 50) == {50, 0}
    end
  end

  describe "maybe_transform_from_address/1 and maybe_transform_to_address/1" do
    test "transforms zero address to mint/burn" do
      zero = "0x0000000000000000000000000000000000000000"
      assert Transform.maybe_transform_from_address(zero) == "mint"
      assert Transform.maybe_transform_to_address(zero) == "burn"
    end

    test "passes other addresses through" do
      addr = "0x1234567890abcdef"
      assert Transform.maybe_transform_from_address(addr) == addr
      assert Transform.maybe_transform_to_address(addr) == addr
    end
  end

  describe "rename_map_keys!/2" do
    test "renames specified keys" do
      result = Transform.rename_map_keys!(%{a: 1, b: 2}, old_keys: [:a], new_keys: [:c])
      assert result == %{c: 1, b: 2}
    end

    test "leaves unspecified keys unchanged" do
      result = Transform.rename_map_keys!(%{a: 1, b: 2, d: 3}, old_keys: [:a], new_keys: [:c])
      assert result[:b] == 2
      assert result[:d] == 3
    end
  end
end
