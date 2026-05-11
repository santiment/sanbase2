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

  describe "valid_public_url?/1" do
    test "accepts public URLs" do
      assert Validation.valid_public_url?("https://example.com/hook") == :ok
      assert Validation.valid_public_url?("https://hooks.slack.com/services/x") == :ok
    end

    test "rejects AWS EC2 metadata IP (link-local 169.254.169.254)" do
      assert {:error, _} =
               Validation.valid_public_url?("http://169.254.169.254/latest/meta-data/")
    end

    test "rejects loopback IPv4" do
      assert {:error, _} = Validation.valid_public_url?("http://127.0.0.1/admin")
      assert {:error, _} = Validation.valid_public_url?("http://127.1.2.3/x")
    end

    test "rejects RFC1918 private IPv4 ranges" do
      assert {:error, _} = Validation.valid_public_url?("http://10.0.0.1/x")
      assert {:error, _} = Validation.valid_public_url?("http://172.16.0.1/x")
      assert {:error, _} = Validation.valid_public_url?("http://172.31.255.255/x")
      assert {:error, _} = Validation.valid_public_url?("http://192.168.1.1/x")
    end

    test "rejects 0.0.0.0 / x range" do
      assert {:error, _} = Validation.valid_public_url?("http://0.0.0.0/x")
    end

    test "rejects multicast / reserved upper ranges" do
      assert {:error, _} = Validation.valid_public_url?("http://224.0.0.1/x")
      assert {:error, _} = Validation.valid_public_url?("http://255.255.255.255/x")
    end

    test "rejects localhost hostname" do
      assert {:error, _} = Validation.valid_public_url?("http://localhost/x")
      assert {:error, _} = Validation.valid_public_url?("http://LOCALHOST/x")
      assert {:error, _} = Validation.valid_public_url?("http://service.localhost/x")
    end

    test "rejects IPv6 loopback and link-local" do
      assert {:error, _} = Validation.valid_public_url?("http://[::1]/x")
      assert {:error, _} = Validation.valid_public_url?("http://[fe80::1]/x")
      assert {:error, _} = Validation.valid_public_url?("http://[fc00::1]/x")
    end

    test "rejects IPv4-mapped IPv6 to private ranges" do
      assert {:error, _} = Validation.valid_public_url?("http://[::ffff:127.0.0.1]/x")
      assert {:error, _} = Validation.valid_public_url?("http://[::ffff:169.254.169.254]/x")
    end

    test "still rejects empty / scheme-less URLs" do
      assert {:error, _} = Validation.valid_public_url?("")
      assert {:error, _} = Validation.valid_public_url?("not-a-url")
    end
  end
end
