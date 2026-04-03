defmodule Sanbase.Alert.OperationEvaluationTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.OperationEvaluation

  describe "above" do
    test "triggers when value is above threshold" do
      assert OperationEvaluation.operation_triggered?(10, %{above: 5})
    end

    test "does not trigger when value equals threshold" do
      refute OperationEvaluation.operation_triggered?(5, %{above: 5})
    end

    test "does not trigger when value is below threshold" do
      refute OperationEvaluation.operation_triggered?(3, %{above: 5})
    end

    test "handles current map format" do
      assert OperationEvaluation.operation_triggered?(%{current: 10}, %{above: 5})
      refute OperationEvaluation.operation_triggered?(%{current: nil}, %{above: 5})
    end
  end

  describe "below" do
    test "triggers when value is below threshold" do
      assert OperationEvaluation.operation_triggered?(3, %{below: 5})
    end

    test "does not trigger when value equals threshold" do
      refute OperationEvaluation.operation_triggered?(5, %{below: 5})
    end

    test "handles current map format" do
      assert OperationEvaluation.operation_triggered?(%{current: 3}, %{below: 5})
      refute OperationEvaluation.operation_triggered?(%{current: nil}, %{below: 5})
    end
  end

  describe "above_or_equal" do
    test "triggers when value equals threshold" do
      assert OperationEvaluation.operation_triggered?(5, %{above_or_equal: 5})
    end

    test "triggers when value is above threshold" do
      assert OperationEvaluation.operation_triggered?(10, %{above_or_equal: 5})
    end

    test "does not trigger when value is below threshold" do
      refute OperationEvaluation.operation_triggered?(3, %{above_or_equal: 5})
    end
  end

  describe "below_or_equal" do
    test "triggers when value equals threshold" do
      assert OperationEvaluation.operation_triggered?(5, %{below_or_equal: 5})
    end

    test "triggers when value is below threshold" do
      assert OperationEvaluation.operation_triggered?(3, %{below_or_equal: 5})
    end

    test "does not trigger when value is above threshold" do
      refute OperationEvaluation.operation_triggered?(10, %{below_or_equal: 5})
    end
  end

  describe "inside_channel" do
    test "triggers when value is inside the channel" do
      assert OperationEvaluation.operation_triggered?(5, %{inside_channel: [1, 10]})
    end

    test "triggers at channel boundaries" do
      assert OperationEvaluation.operation_triggered?(1, %{inside_channel: [1, 10]})
      assert OperationEvaluation.operation_triggered?(10, %{inside_channel: [1, 10]})
    end

    test "does not trigger when value is outside" do
      refute OperationEvaluation.operation_triggered?(0, %{inside_channel: [1, 10]})
      refute OperationEvaluation.operation_triggered?(11, %{inside_channel: [1, 10]})
    end
  end

  describe "outside_channel" do
    test "triggers when value is outside the channel" do
      assert OperationEvaluation.operation_triggered?(0, %{outside_channel: [1, 10]})
      assert OperationEvaluation.operation_triggered?(11, %{outside_channel: [1, 10]})
    end

    test "triggers at channel boundaries" do
      assert OperationEvaluation.operation_triggered?(1, %{outside_channel: [1, 10]})
      assert OperationEvaluation.operation_triggered?(10, %{outside_channel: [1, 10]})
    end

    test "does not trigger when value is inside" do
      refute OperationEvaluation.operation_triggered?(5, %{outside_channel: [1, 10]})
    end
  end

  describe "percent_up" do
    test "triggers when percent change exceeds threshold" do
      assert OperationEvaluation.operation_triggered?(10.0, %{percent_up: 5.0})
    end

    test "triggers at exact threshold" do
      assert OperationEvaluation.operation_triggered?(5.0, %{percent_up: 5.0})
    end

    test "does not trigger for negative percent change" do
      refute OperationEvaluation.operation_triggered?(-10.0, %{percent_up: 5.0})
    end

    test "handles percent_change map format" do
      assert OperationEvaluation.operation_triggered?(%{percent_change: 10.0}, %{percent_up: 5.0})
      refute OperationEvaluation.operation_triggered?(%{percent_change: nil}, %{percent_up: 5.0})
    end
  end

  describe "percent_down" do
    test "triggers when negative percent change exceeds threshold" do
      assert OperationEvaluation.operation_triggered?(-10.0, %{percent_down: 5.0})
    end

    test "does not trigger for positive percent change" do
      refute OperationEvaluation.operation_triggered?(10.0, %{percent_down: 5.0})
    end

    test "handles percent_change map format" do
      assert OperationEvaluation.operation_triggered?(
               %{percent_change: -10.0},
               %{percent_down: 5.0}
             )
    end
  end

  describe "amount_up" do
    test "triggers when absolute change exceeds threshold" do
      assert OperationEvaluation.operation_triggered?(%{absolute_change: 100}, %{amount_up: 50})
    end

    test "does not trigger for negative absolute change" do
      refute OperationEvaluation.operation_triggered?(%{absolute_change: -100}, %{amount_up: 50})
    end
  end

  describe "amount_down" do
    test "triggers when negative absolute change exceeds threshold" do
      assert OperationEvaluation.operation_triggered?(
               %{absolute_change: -100},
               %{amount_down: 50}
             )
    end

    test "does not trigger for positive absolute change" do
      refute OperationEvaluation.operation_triggered?(%{absolute_change: 100}, %{amount_down: 50})
    end
  end

  describe "combinators" do
    test "all_of requires all operations to match" do
      ops = %{all_of: [%{above: 5}, %{below: 15}]}
      assert OperationEvaluation.operation_triggered?(10, ops)
      refute OperationEvaluation.operation_triggered?(3, ops)
      refute OperationEvaluation.operation_triggered?(20, ops)
    end

    test "some_of requires at least one operation to match" do
      ops = %{some_of: [%{above: 100}, %{below: 5}]}
      assert OperationEvaluation.operation_triggered?(3, ops)
      assert OperationEvaluation.operation_triggered?(200, ops)
      refute OperationEvaluation.operation_triggered?(50, ops)
    end

    test "none_of requires no operations to match" do
      ops = %{none_of: [%{above: 100}, %{below: 5}]}
      assert OperationEvaluation.operation_triggered?(50, ops)
      refute OperationEvaluation.operation_triggered?(3, ops)
      refute OperationEvaluation.operation_triggered?(200, ops)
    end
  end

  describe "nil handling" do
    test "nil value never triggers" do
      refute OperationEvaluation.operation_triggered?(nil, %{above: 5})
    end

    test "catch-all returns false for unknown operations" do
      refute OperationEvaluation.operation_triggered?(10, %{unknown_op: 5})
    end
  end
end
