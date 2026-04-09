defmodule Sanbase.DateTimeUtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.DateTimeUtils

  describe "to_human_readable/1" do
    test "formats datetime as human readable string" do
      assert DateTimeUtils.to_human_readable(~U[2021-01-12 12:45:56Z]) == "12 Jan 2021 12:45 UTC"
      assert DateTimeUtils.to_human_readable(~U[1992-11-10 04:41:12Z]) == "10 Nov 1992 04:41 UTC"
      assert DateTimeUtils.to_human_readable(~U[2012-12-31 22:12:12Z]) == "31 Dec 2012 22:12 UTC"
    end
  end

  describe "str_to_sec/1" do
    test "parses nanoseconds" do
      assert DateTimeUtils.str_to_sec("10000000000ns") == 10
    end

    test "parses seconds" do
      assert DateTimeUtils.str_to_sec("30s") == 30
    end

    test "parses minutes" do
      assert DateTimeUtils.str_to_sec("5m") == 300
    end

    test "parses hours" do
      assert DateTimeUtils.str_to_sec("2h") == 7200
    end

    test "parses days" do
      assert DateTimeUtils.str_to_sec("1d") == 86_400
    end

    test "parses weeks" do
      assert DateTimeUtils.str_to_sec("1w") == 604_800
    end

    test "parses years" do
      assert DateTimeUtils.str_to_sec("1y") == 365 * 86_400
    end

    test "raises on invalid interval" do
      assert_raise ArgumentError, fn ->
        DateTimeUtils.str_to_sec("invalid")
      end
    end
  end

  describe "str_to_days/1" do
    test "converts interval to days" do
      assert DateTimeUtils.str_to_days("7d") == 7
    end

    test "truncates partial days" do
      assert DateTimeUtils.str_to_days("36h") == 1
    end
  end

  describe "str_to_hours/1" do
    test "converts interval to hours" do
      assert DateTimeUtils.str_to_hours("2d") == 48
    end

    test "converts hours directly" do
      assert DateTimeUtils.str_to_hours("5h") == 5
    end
  end

  describe "round_datetime/2" do
    test "rounds down to nearest 5-minute boundary by default" do
      dt = ~U[2024-01-01 12:07:33Z]
      result = DateTimeUtils.round_datetime(dt)
      assert result == ~U[2024-01-01 12:05:00Z]
    end

    test "rounds to custom interval" do
      dt = ~U[2024-01-01 12:07:33Z]
      result = DateTimeUtils.round_datetime(dt, second: 3600)
      assert result == ~U[2024-01-01 12:00:00Z]
    end

    test "returns unchanged when interval is 0" do
      dt = ~U[2024-01-01 12:07:33Z]
      result = DateTimeUtils.round_datetime(dt, second: 0)
      assert result == dt
    end

    test "rounds up when rounding option is :up" do
      dt = ~U[2024-01-01 12:07:33Z]
      result = DateTimeUtils.round_datetime(dt, second: 3600, rounding: :up)
      assert result == ~U[2024-01-01 13:00:00Z]
    end
  end

  describe "interval_to_str/1" do
    test "converts second intervals" do
      assert DateTimeUtils.interval_to_str("1s") == "1 second"
      assert DateTimeUtils.interval_to_str("5s") == "5 seconds"
    end

    test "converts minute intervals" do
      assert DateTimeUtils.interval_to_str("1m") == "1 minute"
      assert DateTimeUtils.interval_to_str("30m") == "30 minutes"
    end

    test "converts hour intervals" do
      assert DateTimeUtils.interval_to_str("1h") == "1 hour"
      assert DateTimeUtils.interval_to_str("5h") == "5 hours"
    end

    test "converts day intervals" do
      assert DateTimeUtils.interval_to_str("1d") == "1 day"
      assert DateTimeUtils.interval_to_str("7d") == "7 days"
    end
  end

  describe "valid_interval?/1" do
    test "returns true for valid intervals" do
      assert DateTimeUtils.valid_interval?("1d")
      assert DateTimeUtils.valid_interval?("5m")
      assert DateTimeUtils.valid_interval?("1h")
    end

    test "returns false for invalid intervals" do
      refute DateTimeUtils.valid_interval?("abc")
      refute DateTimeUtils.valid_interval?("")
    end
  end

  describe "valid_compound_duration?/1" do
    test "returns true for valid durations" do
      assert DateTimeUtils.valid_compound_duration?("30s")
      assert DateTimeUtils.valid_compound_duration?("1d")
      assert DateTimeUtils.valid_compound_duration?("1h")
    end

    test "returns false for invalid durations" do
      refute DateTimeUtils.valid_compound_duration?("abc")
      refute DateTimeUtils.valid_compound_duration?("1x")
    end
  end

  describe "to_iso8601/1" do
    test "returns nil for nil" do
      assert DateTimeUtils.to_iso8601(nil) == nil
    end

    test "converts DateTime" do
      dt = ~U[2024-01-01 12:00:00Z]
      assert DateTimeUtils.to_iso8601(dt) == "2024-01-01T12:00:00Z"
    end

    test "converts NaiveDateTime" do
      ndt = ~N[2024-01-01 12:00:00]
      assert DateTimeUtils.to_iso8601(ndt) == "2024-01-01T12:00:00Z"
    end
  end

  describe "from_iso8601!/1" do
    test "parses ISO 8601 string" do
      assert DateTimeUtils.from_iso8601!("2024-01-01T12:00:00Z") == ~U[2024-01-01 12:00:00Z]
    end

    test "passes through DateTime unchanged" do
      dt = ~U[2024-01-01 12:00:00Z]
      assert DateTimeUtils.from_iso8601!(dt) == dt
    end
  end

  describe "time_in_range?/3" do
    test "returns true when time is in range" do
      assert DateTimeUtils.time_in_range?(~T[12:30:00], ~T[12:00:00], ~T[13:00:00])
    end

    test "returns false when time is outside range" do
      refute DateTimeUtils.time_in_range?(~T[14:00:00], ~T[12:00:00], ~T[13:00:00])
    end

    test "returns false when from equals to" do
      refute DateTimeUtils.time_in_range?(~T[12:00:00], ~T[12:00:00], ~T[12:00:00])
    end

    test "handles wrapping ranges (e.g. 23:00 - 01:00)" do
      assert DateTimeUtils.time_in_range?(~T[23:30:00], ~T[23:00:00], ~T[01:00:00])
      assert DateTimeUtils.time_in_range?(~T[00:30:00], ~T[23:00:00], ~T[01:00:00])
      refute DateTimeUtils.time_in_range?(~T[12:00:00], ~T[23:00:00], ~T[01:00:00])
    end
  end

  describe "truncate_datetimes/2" do
    test "truncates DateTime values in map" do
      dt = %DateTime{
        year: 2024,
        month: 1,
        day: 1,
        hour: 12,
        minute: 0,
        second: 0,
        microsecond: {123_456, 6},
        zone_abbr: "UTC",
        utc_offset: 0,
        std_offset: 0,
        time_zone: "Etc/UTC"
      }

      result = DateTimeUtils.truncate_datetimes(%{time: dt, name: "test"})
      assert result.time.microsecond == {0, 0}
      assert result.name == "test"
    end

    test "leaves non-datetime values unchanged" do
      result = DateTimeUtils.truncate_datetimes(%{a: 1, b: "hello"})
      assert result == %{a: 1, b: "hello"}
    end
  end

  describe "generate_dates_inclusive/2" do
    test "generates all dates in range" do
      from = ~D[2024-01-01]
      to = ~D[2024-01-03]
      result = DateTimeUtils.generate_dates_inclusive(from, to)
      assert result == [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]]
    end

    test "returns single date when from equals to" do
      date = ~D[2024-01-01]
      assert DateTimeUtils.generate_dates_inclusive(date, date) == [date]
    end

    test "returns empty list when from is after to" do
      assert DateTimeUtils.generate_dates_inclusive(~D[2024-01-03], ~D[2024-01-01]) == []
    end
  end

  describe "seconds_ago/2 and seconds_after/2 with explicit datetime" do
    test "seconds_ago subtracts from given datetime" do
      dt = ~U[2024-01-01 12:00:00Z]
      result = DateTimeUtils.seconds_ago(3600, dt)
      assert DateTime.truncate(result, :second) == ~U[2024-01-01 11:00:00Z]
    end

    test "seconds_after adds to given datetime" do
      dt = ~U[2024-01-01 12:00:00Z]
      result = DateTimeUtils.seconds_after(3600, dt)
      assert DateTime.truncate(result, :second) == ~U[2024-01-01 13:00:00Z]
    end

    test "days_after adds days to given datetime" do
      dt = ~U[2024-01-01 00:00:00Z]
      result = DateTimeUtils.days_after(2, dt)
      assert DateTime.truncate(result, :second) == ~U[2024-01-03 00:00:00Z]
    end
  end

  describe "date_to_datetime/2" do
    test "converts Date to DateTime at midnight" do
      result = DateTimeUtils.date_to_datetime(~D[2024-01-01])
      assert result == ~U[2024-01-01 00:00:00Z]
    end

    test "converts Date to DateTime at given time" do
      result = DateTimeUtils.date_to_datetime(~D[2024-01-01], time: ~T[12:30:00])
      assert result == ~U[2024-01-01 12:30:00Z]
    end
  end
end
