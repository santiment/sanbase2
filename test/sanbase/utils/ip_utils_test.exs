defmodule Sanbase.Utils.IPTest do
  use ExUnit.Case, async: true

  alias Sanbase.Utils.IP

  describe "private_or_reserved?/1 with IPv4 tuples" do
    test "rejects loopback 127.0.0.0/8" do
      assert IP.private_or_reserved?({127, 0, 0, 1})
      assert IP.private_or_reserved?({127, 200, 0, 1})
    end

    test "rejects 0.0.0.0/8" do
      assert IP.private_or_reserved?({0, 0, 0, 0})
      assert IP.private_or_reserved?({0, 1, 2, 3})
    end

    test "rejects RFC1918 private ranges" do
      assert IP.private_or_reserved?({10, 0, 0, 1})
      assert IP.private_or_reserved?({172, 16, 0, 1})
      assert IP.private_or_reserved?({172, 31, 255, 255})
      assert IP.private_or_reserved?({192, 168, 1, 1})
    end

    test "accepts public 172.x outside 16..31" do
      refute IP.private_or_reserved?({172, 15, 0, 1})
      refute IP.private_or_reserved?({172, 32, 0, 1})
    end

    test "rejects link-local 169.254.0.0/16 (AWS metadata)" do
      assert IP.private_or_reserved?({169, 254, 169, 254})
    end

    test "rejects carrier-grade NAT 100.64.0.0/10" do
      assert IP.private_or_reserved?({100, 64, 0, 1})
      assert IP.private_or_reserved?({100, 127, 255, 255})
    end

    test "rejects multicast and reserved upper ranges (>= 224)" do
      assert IP.private_or_reserved?({224, 0, 0, 1})
      assert IP.private_or_reserved?({255, 255, 255, 255})
    end

    test "accepts public IPv4 addresses" do
      refute IP.private_or_reserved?({8, 8, 8, 8})
      refute IP.private_or_reserved?({1, 1, 1, 1})
      refute IP.private_or_reserved?({93, 184, 216, 34})
    end
  end

  describe "private_or_reserved?/1 with IPv6 tuples" do
    test "rejects unspecified and loopback" do
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0, 0, 0})
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0, 0, 1})
    end

    test "rejects link-local fe80::/10" do
      assert IP.private_or_reserved?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
      assert IP.private_or_reserved?({0xFEBF, 0, 0, 0, 0, 0, 0, 1})
    end

    test "rejects unique-local fc00::/7" do
      assert IP.private_or_reserved?({0xFC00, 0, 0, 0, 0, 0, 0, 1})
      assert IP.private_or_reserved?({0xFDFF, 0, 0, 0, 0, 0, 0, 1})
    end

    test "rejects IPv4-mapped IPv6 to private ranges" do
      # ::ffff:127.0.0.1
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001})
      # ::ffff:169.254.169.254
      assert IP.private_or_reserved?({0, 0, 0, 0, 0, 0xFFFF, 0xA9FE, 0xA9FE})
    end

    test "accepts public IPv6 addresses" do
      refute IP.private_or_reserved?({0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888})
    end
  end

  describe "blocked_host?/1 with strings" do
    test "rejects literal private/loopback IPv4" do
      assert IP.blocked_host?("127.0.0.1")
      assert IP.blocked_host?("169.254.169.254")
      assert IP.blocked_host?("10.0.0.1")
      assert IP.blocked_host?("192.168.1.1")
    end

    test "rejects literal IPv6 loopback" do
      assert IP.blocked_host?("::1")
    end

    test "rejects localhost hostname (case-insensitive)" do
      assert IP.blocked_host?("localhost")
      assert IP.blocked_host?("LOCALHOST")
      assert IP.blocked_host?("api.localhost")
    end

    test "accepts public hostnames and IPs" do
      refute IP.blocked_host?("example.com")
      refute IP.blocked_host?("hooks.slack.com")
      refute IP.blocked_host?("8.8.8.8")
      refute IP.blocked_host?("metadata.google.internal")
    end
  end
end
