defmodule Sanbase.Alert.History.ResultBuilder.TransformerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.History.ResultBuilder.Transformer

  doctest Sanbase.Alert.History.ResultBuilder.Transformer

  describe "transform/3" do
    test "calculates percent and absolute change over time window" do
      data = [
        %{value: 100, datetime: ~U[2024-01-01 00:00:00Z]},
        %{value: 150, datetime: ~U[2024-01-02 00:00:00Z]},
        %{value: 200, datetime: ~U[2024-01-03 00:00:00Z]}
      ]

      result = Transformer.transform(data, "1d", :value)

      assert [first, second] = result
      assert first.current == 150
      assert first.absolute_change == 50
      assert first.percent_change == 50.0
      assert first.datetime == ~U[2024-01-02 00:00:00Z]

      assert second.current == 200
      assert second.absolute_change == 50
    end

    test "handles custom value key" do
      data = [
        %{price: 10, datetime: ~U[2024-01-01 00:00:00Z]},
        %{price: 20, datetime: ~U[2024-01-02 00:00:00Z]},
        %{price: 15, datetime: ~U[2024-01-03 00:00:00Z]}
      ]

      result = Transformer.transform(data, "1d", :price)

      assert [first, second] = result
      assert first.current == 20
      assert first.absolute_change == 10
      assert second.current == 15
      assert second.absolute_change == -5
    end

    test "returns empty list when data is shorter than time window" do
      data = [
        %{value: 100, datetime: ~U[2024-01-01 00:00:00Z]}
      ]

      assert Transformer.transform(data, "1d", :value) == []
    end

    test "returns empty list for empty input" do
      assert Transformer.transform([], "1d", :value) == []
    end

    test "handles zero starting value (percent change from 0)" do
      data = [
        %{value: 0, datetime: ~U[2024-01-01 00:00:00Z]},
        %{value: 100, datetime: ~U[2024-01-02 00:00:00Z]},
        %{value: 200, datetime: ~U[2024-01-03 00:00:00Z]}
      ]

      result = Transformer.transform(data, "1d", :value)
      assert [first, _second] = result
      assert first.absolute_change == 100
    end
  end
end
