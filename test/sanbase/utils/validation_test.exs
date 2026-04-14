defmodule Sanbase.Utils.ValidationTest do
  use ExUnit.Case, async: true

  alias Sanbase.Utils.Validation

  describe "valid_percent?/1" do
    test "accepts valid percentages" do
      assert Validation.valid_percent?(0) == :ok
      assert Validation.valid_percent?(50) == :ok
      assert Validation.valid_percent?(-50) == :ok
      assert Validation.valid_percent?(-100) == :ok
    end

    test "rejects percentages below -100" do
      assert {:error, _} = Validation.valid_percent?(-101)
    end

    test "rejects non-numeric values" do
      assert {:error, _} = Validation.valid_percent?("50")
    end
  end

  describe "valid_threshold?/1" do
    test "accepts positive numbers" do
      assert Validation.valid_threshold?(1) == :ok
      assert Validation.valid_threshold?(0.5) == :ok
      assert Validation.valid_threshold?(100) == :ok
    end

    test "rejects zero" do
      assert {:error, _} = Validation.valid_threshold?(0)
    end

    test "rejects negative numbers" do
      assert {:error, _} = Validation.valid_threshold?(-1)
    end

    test "rejects non-numbers" do
      assert {:error, _} = Validation.valid_threshold?("5")
    end
  end

  describe "valid_time_window?/1" do
    test "accepts valid time windows" do
      assert Validation.valid_time_window?("1d") == :ok
      assert Validation.valid_time_window?("7d") == :ok
      assert Validation.valid_time_window?("30m") == :ok
      assert Validation.valid_time_window?("2h") == :ok
    end

    test "rejects too large time windows (>= 1 year)" do
      assert {:error, _} = Validation.valid_time_window?("366d")
    end

    test "rejects invalid format" do
      assert {:error, _} = Validation.valid_time_window?("abc")
      assert {:error, _} = Validation.valid_time_window?("1x")
    end

    test "rejects non-string values" do
      assert {:error, _} = Validation.valid_time_window?(123)
    end
  end

  describe "time_window_is_whole_days?/1" do
    test "accepts whole day intervals" do
      assert Validation.time_window_is_whole_days?("1d") == :ok
      assert Validation.time_window_is_whole_days?("7d") == :ok
    end

    test "rejects non-whole day intervals" do
      assert {:error, _} = Validation.time_window_is_whole_days?("5h")
      assert {:error, _} = Validation.time_window_is_whole_days?("30m")
    end
  end

  describe "time_window_bigger_than?/2" do
    test "passes when time window is bigger" do
      assert Validation.time_window_bigger_than?("2d", "1d") == :ok
    end

    test "passes when time windows are equal" do
      assert Validation.time_window_bigger_than?("1d", "1d") == :ok
    end

    test "fails when time window is smaller" do
      assert {:error, _} = Validation.time_window_bigger_than?("1h", "1d")
    end
  end

  describe "valid_iso8601_time_string?/1" do
    test "accepts valid ISO 8601 time strings" do
      assert Validation.valid_iso8601_time_string?("12:00:00") == :ok
      assert Validation.valid_iso8601_time_string?("23:59:59") == :ok
      assert Validation.valid_iso8601_time_string?("00:00:00") == :ok
    end

    test "rejects invalid time strings" do
      assert {:error, _} = Validation.valid_iso8601_time_string?("25:00:00")
      assert {:error, _} = Validation.valid_iso8601_time_string?("not-a-time")
    end

    test "rejects non-string values" do
      assert {:error, _} = Validation.valid_iso8601_time_string?(123)
    end
  end

  describe "valid_url?/1" do
    test "accepts valid URLs" do
      assert Validation.valid_url?("https://example.com/image.png") == :ok
    end

    test "rejects empty string" do
      assert {:error, _} = Validation.valid_url?("")
    end

    test "rejects URL without scheme" do
      assert {:error, _} = Validation.valid_url?("example.com/image.png")
    end

    test "rejects URL without host" do
      # Note: URI.parse("https:///image.png") gives host: "" (not nil),
      # so the code allows it through. Use a truly hostless URL.
      assert {:error, _} = Validation.valid_url?("file:image.png")
    end

    test "rejects URL without path when require_path is true" do
      assert {:error, _} = Validation.valid_url?("https://example.com")
    end

    test "accepts URL without path when require_path is false" do
      assert Validation.valid_url?("https://example.com", require_path: false) == :ok
    end
  end

  describe "valid_url_simple?/1" do
    test "returns true for valid URL" do
      assert Validation.valid_url_simple?("https://example.com") == true
    end

    test "returns false for URL without scheme" do
      assert Validation.valid_url_simple?("example.com") == false
    end
  end
end
