defmodule Sanbase.DateTimeUtilsTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.DateTimeUtils

  test "#compound_duration_to_seconds/1" do
    assert DateTimeUtils.compound_duration_to_seconds("10000000000ns") == 10
    assert DateTimeUtils.compound_duration_to_seconds("100s") == 100
    assert DateTimeUtils.compound_duration_to_seconds("1m") == 60
    assert DateTimeUtils.compound_duration_to_seconds("1h") == 3600
    assert DateTimeUtils.compound_duration_to_seconds("1d") == 86400
    assert DateTimeUtils.compound_duration_to_seconds("1w") == 604_800
    assert DateTimeUtils.compound_duration_to_seconds("100") == 100
  end

  test "seconds after" do
    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:45:37], "Etc/UTC")

    assert DateTime.compare(
             DateTimeUtils.seconds_after(37, datetime1),
             datetime2
           ) == :eq
  end

  test "seconds ago" do
    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:45:37], "Etc/UTC")

    assert DateTime.compare(
             DateTimeUtils.seconds_ago(37, datetime2),
             datetime1
           ) == :eq
  end
end
