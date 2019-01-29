defmodule Sanbase.Signals.Evaluator.CacheTest do
  use Sanbase.DataCase, async: false
  alias Sanbase.Signals.Evaluator.Cache

  test "value is correctly calculated and returned" do
    result = Cache.get_or_store("some_key", fn -> 123_456 end)

    assert result == 123_456
  end

  test "second call for the same key does not precalculated" do
    cache_key = "key"
    value = 123_456
    self = self()
    message = "Value send from calculating function"

    fun = fn ->
      send(self, message)
      value
    end

    result = Cache.get_or_store(cache_key, fun)
    assert result == value
    assert_receive(^message)

    result2 = Cache.get_or_store(cache_key, fun)
    assert result2 == value
    refute_receive(^message)
  end
end
