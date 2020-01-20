defmodule Sanbase.DateTimeUtilsTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.DateTimeUtils

  test "#str_to_sec/1" do
    assert DateTimeUtils.str_to_sec("10000000000ns") == 10
    assert DateTimeUtils.str_to_sec("100s") == 100
    assert DateTimeUtils.str_to_sec("1m") == 60
    assert DateTimeUtils.str_to_sec("1h") == 3600
    assert DateTimeUtils.str_to_sec("1d") == 86_400
    assert DateTimeUtils.str_to_sec("1w") == 604_800

    assert_raise CaseClauseError, fn ->
      DateTimeUtils.str_to_sec("100") == 100
    end

    assert_raise CaseClauseError, fn ->
      DateTimeUtils.str_to_sec("1dd") == 100
    end
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

  test "time in range" do
    assert DateTimeUtils.time_in_range?(~T[12:00:00], ~T[13:00:00], ~T[14:00:00]) == false
    assert DateTimeUtils.time_in_range?(~T[13:00:00], ~T[12:00:00], ~T[14:00:00]) == true
    # from == to is not a range
    assert DateTimeUtils.time_in_range?(~T[13:00:00], ~T[13:00:00], ~T[13:00:00]) == false
    assert DateTimeUtils.time_in_range?(~T[23:55:00], ~T[23:50:00], ~T[23:59:00]) == true
    assert DateTimeUtils.time_in_range?(~T[23:55:00], ~T[23:50:00], ~T[00:10:00]) == true
  end
end
