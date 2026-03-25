defmodule Sanbase.Alert.UtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.Utils

  doctest Sanbase.Alert.Utils

  describe "round_price/1" do
    test "rounds small prices (0 < price < 1) to 6 decimal places" do
      assert Utils.round_price(0.123456789) == 0.123457
    end

    test "rounds prices >= 1 to 2 decimal places" do
      assert Utils.round_price(1234.5678) == 1234.57
    end

    test "handles integer prices" do
      assert Utils.round_price(10) == 10.0
    end

    test "handles price exactly 1" do
      assert Utils.round_price(1) == 1.0
    end

    test "handles very small prices close to 0" do
      assert Utils.round_price(0.000001234) == 0.000001
    end
  end

  describe "construct_cache_key/1" do
    test "returns a 32-character binary string" do
      key = Utils.construct_cache_key([1, 2, 3])
      assert is_binary(key)
      assert byte_size(key) == 32
    end

    test "same input produces same key" do
      key1 = Utils.construct_cache_key(["a", "b", "c"])
      key2 = Utils.construct_cache_key(["a", "b", "c"])
      assert key1 == key2
    end

    test "different input produces different key" do
      key1 = Utils.construct_cache_key([1, 2, 3])
      key2 = Utils.construct_cache_key([3, 2, 1])
      assert key1 != key2
    end

    test "handles mixed types" do
      key = Utils.construct_cache_key(["metric", 42, :atom])
      assert is_binary(key)
      assert byte_size(key) == 32
    end

    test "handles empty list" do
      key = Utils.construct_cache_key([])
      assert is_binary(key)
      assert byte_size(key) == 32
    end
  end
end
