defmodule Sanbase.Clickhouse.MetricAdapter.LabeledBalance.CompareTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.MetricAdapter.LabeledBalance.Compare

  @dt1 ~U[2026-10-10 00:00:00Z]
  @dt2 ~U[2026-10-11 00:00:00Z]
  @dt3 ~U[2026-10-12 00:00:00Z]

  test "equal values are not reported" do
    data = %{{"ethereum", @dt1} => 1.0, {"ethereum", @dt2} => 0}
    delta = %{{"ethereum", @dt1} => 1, {"ethereum", @dt2} => 0.0}

    assert %{points: 2, differ: 0, diffs: [], max_relative_diff: +0.0} =
             Compare.compare(data, delta)
  end

  test "different and missing values are reported" do
    legacy = %{{"ethereum", @dt1} => 100.0, {"ethereum", @dt2} => 100.0}

    delta = %{
      {"ethereum", @dt1} => 100.0000001,
      {"ethereum", @dt2} => 90.0,
      {"ethereum", @dt3} => 5.0
    }

    result = Compare.compare(legacy, delta)

    assert %{points: 3, differ: 2, only_legacy: 0, only_delta: 1} = result
    assert result.max_relative_diff == :infinity

    assert [
             %{datetime: @dt2, legacy: 100.0, delta: 90.0, relative_diff: diff},
             %{datetime: @dt3, legacy: nil, delta: 5.0}
           ] = result.diffs

    assert_in_delta diff, 0.1, 1.0e-9
  end

  test "the tolerance is used" do
    legacy = %{{"ethereum", @dt1} => 100.0}
    delta = %{{"ethereum", @dt1} => 100.5}

    assert %{differ: 1} = Compare.compare(legacy, delta)
    assert %{differ: 0} = Compare.compare(legacy, delta, 0.01)
  end
end
