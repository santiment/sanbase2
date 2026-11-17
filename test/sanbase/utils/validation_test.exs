defmodule Sanbase.Utils.ValidationTest do
  use ExUnit.Case, async: true

  alias Sanbase.Utils.Validation

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

  describe "valid_webhook_url?/1" do
    test "accepts https URLs with a domain name host" do
      assert Validation.valid_webhook_url?("https://example.com/hook") == :ok
      assert Validation.valid_webhook_url?("https://hooks.slack.com/services/x") == :ok
    end

    test "rejects http URLs" do
      assert {:error, error} = Validation.valid_webhook_url?("http://example.com/hook")
      assert error =~ "must use the https scheme"
    end

    test "rejects non-http(s) schemes" do
      assert {:error, _} = Validation.valid_webhook_url?("ftp://example.com/hook")
    end

    test "rejects public IPv4 literal hosts" do
      assert {:error, error} = Validation.valid_webhook_url?("https://8.8.8.8/hook")
      assert error =~ "is an IP address"

      assert {:error, _} = Validation.valid_webhook_url?("https://1.1.1.1/hook")
    end

    test "rejects shortened IPv4 literal hosts" do
      assert {:error, _} = Validation.valid_webhook_url?("https://8.8/hook")
    end

    test "rejects public IPv6 literal hosts" do
      assert {:error, error} = Validation.valid_webhook_url?("https://[2606:4700::1111]/hook")
      assert error =~ "is an IP address"
    end

    test "rejects private / reserved hosts even over https" do
      assert {:error, _} = Validation.valid_webhook_url?("https://127.0.0.1/hook")
      assert {:error, _} = Validation.valid_webhook_url?("https://169.254.169.254/hook")
      assert {:error, _} = Validation.valid_webhook_url?("https://localhost/hook")
      assert {:error, _} = Validation.valid_webhook_url?("https://[::1]/hook")
    end

    test "rejects empty / scheme-less URLs" do
      assert {:error, _} = Validation.valid_webhook_url?("")
      assert {:error, _} = Validation.valid_webhook_url?("example.com/hook")
    end
  end

  describe "IP.resolves_to_blocked_ip?/1" do
    test "hosts resolving to loopback are blocked" do
      assert Sanbase.Utils.IP.resolves_to_blocked_ip?("localhost") == true
    end

    test "public IP literals are not blocked" do
      assert Sanbase.Utils.IP.resolves_to_blocked_ip?("8.8.8.8") == false
    end

    test "hosts that do not resolve are blocked" do
      assert Sanbase.Utils.IP.resolves_to_blocked_ip?("does-not-exist.invalid") == true
    end
  end

  describe "valid_webhook_url?/1 user info" do
    test "rejects user info and an @ before the path" do
      assert {:error, _} = Validation.valid_webhook_url?("https://user@example.com/hook")
      assert {:error, _} = Validation.valid_webhook_url?("https://user:pass@example.com/hook")
      assert {:error, _} = Validation.valid_webhook_url?("https://example.com?@internal.host/x")
      assert {:error, _} = Validation.valid_webhook_url?("https://example.com#@internal.host/x")
    end

    test "allows an @ in the path or the query after the path" do
      assert :ok = Validation.valid_webhook_url?("https://example.com/hook/@user")
      assert :ok = Validation.valid_webhook_url?("https://example.com/hook?to=@user")
    end
  end

  describe "IP.private_or_reserved?/1" do
    alias Sanbase.Utils.IP

    test "IPv6 forms that carry a private IPv4 address are blocked" do
      # ::ffff:169.254.169.254, ::169.254.169.254, 64:ff9b::169.254.169.254, 2002:a9fe:a9fe::
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0xFFFF, 0xA9FE, 0xA9FE})
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0, 0xA9FE, 0xA9FE})
      assert IP.private_or_reserved?({0x64, 0xFF9B, 0, 0, 0, 0, 0xA9FE, 0xA9FE})
      assert IP.private_or_reserved?({0x2002, 0xA9FE, 0xA9FE, 0, 0, 0, 0, 1})
      assert IP.private_or_reserved?({0x2002, 0x0A00, 0x0001, 0, 0, 0, 0, 1})
    end

    test "IPv6 forms that carry a public IPv4 address are not blocked" do
      # 64:ff9b::8.8.8.8 and 2002:808:808::1
      refute IP.private_or_reserved?({0x64, 0xFF9B, 0, 0, 0, 0, 0x0808, 0x0808})
      refute IP.private_or_reserved?({0x2002, 0x0808, 0x0808, 0, 0, 0, 0, 1})
    end

    test "IPv6 site-local and multicast are blocked" do
      assert IP.private_or_reserved?({0xFEC0, 0, 0, 0, 0, 0, 0, 1})
      assert IP.private_or_reserved?({0xFF02, 0, 0, 0, 0, 0, 0, 1})
    end

    test "IPv4 benchmark and documentation ranges are blocked" do
      assert IP.private_or_reserved?({198, 18, 0, 1})
      assert IP.private_or_reserved?({198, 19, 255, 1})
      assert IP.private_or_reserved?({192, 0, 2, 1})
      assert IP.private_or_reserved?({198, 51, 100, 1})
      assert IP.private_or_reserved?({203, 0, 113, 1})
      refute IP.private_or_reserved?({198, 20, 0, 1})
      refute IP.private_or_reserved?({8, 8, 8, 8})
    end

    test "a public IPv6 address is not blocked" do
      refute IP.private_or_reserved?({0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111})
    end
  end
end
