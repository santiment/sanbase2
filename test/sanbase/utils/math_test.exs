defmodule Sanbase.MathTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Sanbase.Math

  doctest Sanbase.Math

  test "#average" do
    assert Math.mean([4, 6, 8, 2]) == 5.0
    assert Math.mean([]) == 0
    assert Math.mean([0.126], precision: 2) == 0.13
    # default precision is 6 for values < 1
    assert Math.mean([0.123456789]) == 0.123457
    # default precision is 2 for values >= 1
    assert Math.mean([1.123456789]) == 1.12
  end

  property "average is always between min and max when list of integers" do
    check all(list <- list_of(positive_integer(), min_length: 1)) do
      average = Math.mean(list)
      min = Enum.min(list)
      max = Enum.max(list)
      assert average >= min and average <= max
    end
  end

  property "average is always between min minus epsilon and max plus epsilon when floats" do
    # The average rounds after 2 digits
    epsilon = 0.01

    check all(list <- list_of(float(min: 0.00), min_length: 1)) do
      average = Math.mean(list)
      min = Enum.min(list)
      max = Enum.max(list)
      assert average >= min - epsilon and average <= max + epsilon
    end
  end

  describe "round_float/1" do
    test "rounds large floats to 2 decimal places" do
      assert Math.round_float(1.2345) == 1.23
      assert Math.round_float(-5.6789) == -5.68
    end

    test "rounds small floats to 6 decimal places" do
      assert Math.round_float(0.1234567) == 0.123457
    end

    test "rounds near-zero floats to +0.0" do
      assert Math.round_float(0.0000001) == +0.0
      assert Math.round_float(-0.0000001) == +0.0
    end

    test "converts integers to float" do
      assert Math.round_float(5) == 5.0
    end
  end

  describe "percent_of/3" do
    test "calculates percentage between 0 and 100 by default" do
      result = Math.percent_of(25, 100)
      assert result == 25.0
    end

    test "calculates percentage between 0 and 1" do
      result = Math.percent_of(25, 100, type: :between_0_and_1)
      assert result == 0.25
    end

    test "returns nil for invalid inputs" do
      assert Math.percent_of(-1, 100) == nil
      assert Math.percent_of(5, 0) == nil
      assert Math.percent_of(10, 5) == nil
    end
  end

  describe "simple_moving_average/2" do
    test "computes moving average over a window" do
      values = [1, 2, 3, 4, 5]
      result = Math.simple_moving_average(values, 3)
      assert length(result) == 3
      assert hd(result) == 2.0
    end

    test "returns empty list when period exceeds data length" do
      assert Math.simple_moving_average([1, 2], 3) == []
    end
  end

  describe "simple_moving_average/3 with opts" do
    test "computes SMA with value key and datetime" do
      data = [
        %{price: 10, datetime: ~U[2024-01-01 00:00:00Z]},
        %{price: 20, datetime: ~U[2024-01-02 00:00:00Z]},
        %{price: 30, datetime: ~U[2024-01-03 00:00:00Z]}
      ]

      {:ok, result} = Math.simple_moving_average(data, 2, value_key: :price)
      assert length(result) == 2
      assert hd(result)[:price] == 15.0
    end
  end
end
