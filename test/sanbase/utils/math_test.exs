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
end
