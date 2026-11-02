defmodule SanbaseWeb.Plug.ClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias SanbaseWeb.Plug.ClientIp

  @traefik {10, 96, 1, 2}
  @cf_edge "172.71.241.92"
  @client "203.0.113.7"

  describe "cloudflare?/1" do
    test "Cloudflare IPv4 and IPv6 addresses" do
      for ip <- ["172.64.192.56", "104.23.221.5", "141.101.98.64", "162.158.216.144"] do
        assert ClientIp.cloudflare?(parse(ip)), ip
      end

      assert ClientIp.cloudflare?(parse("2606:4700:10::6816:1"))
    end

    test "other addresses" do
      for ip <- ["192.144.23.228", "185.220.101.5", "8.8.8.8", "10.0.0.1", "172.63.255.255"] do
        refute ClientIp.cloudflare?(parse(ip)), ip
      end

      refute ClientIp.cloudflare?(parse("2001:db8::1"))
    end
  end

  describe "client_ip/2" do
    test "through Cloudflare: CF-Connecting-IP is used" do
      headers = [{"x-forwarded-for", @cf_edge}, {"cf-connecting-ip", @client}]

      assert ClientIp.client_ip(headers, @traefik) == parse(@client)
    end

    test "through Cloudflare with the full chain in X-Forwarded-For" do
      headers = [{"x-forwarded-for", "#{@client}, #{@cf_edge}"}]

      assert ClientIp.client_ip(headers, @traefik) == parse(@client)
    end

    test "through Cloudflare: a client-forged X-Forwarded-For entry is not trusted" do
      # Cloudflare appends the real client after whatever the client sent.
      headers = [
        {"x-forwarded-for", "1.2.3.4, #{@client}, #{@cf_edge}"},
        {"cf-connecting-ip", @client}
      ]

      assert ClientIp.client_ip(headers, @traefik) == parse(@client)
    end

    test "not through Cloudflare: a forged CF-Connecting-IP is ignored" do
      attacker = "192.144.23.228"
      headers = [{"x-forwarded-for", attacker}, {"cf-connecting-ip", "1.2.3.4"}]

      assert ClientIp.client_ip(headers, @traefik) == parse(attacker)
    end

    test "not through Cloudflare: a forged Cloudflare hop in X-Forwarded-For is ignored" do
      attacker = "192.144.23.228"
      headers = [{"x-forwarded-for", "1.2.3.4, #{@cf_edge}, #{attacker}"}]

      assert ClientIp.client_ip(headers, @traefik) == parse(attacker)
    end

    test "an invalid CF-Connecting-IP falls back to X-Forwarded-For" do
      headers = [{"x-forwarded-for", "#{@client}, #{@cf_edge}"}, {"cf-connecting-ip", "junk"}]

      assert ClientIp.client_ip(headers, @traefik) == parse(@client)
    end

    test "in-cluster hops (100.64.0.0/10) are skipped" do
      headers = [{"x-forwarded-for", "#{@client}, #{@cf_edge}, 100.96.13.164"}]
      assert ClientIp.client_ip(headers, @traefik) == parse(@client)

      headers = [{"x-forwarded-for", "#{@client}, 100.96.13.164"}]
      assert ClientIp.client_ip(headers, @traefik) == parse(@client)
    end

    test "only private hops (in-cluster call): the peer address is kept" do
      assert ClientIp.client_ip([{"x-forwarded-for", "10.0.0.5"}], @traefik) == @traefik
      assert ClientIp.client_ip([], @traefik) == @traefik
    end
  end

  test "the plug sets conn.remote_ip and the logger metadata" do
    conn =
      conn(:get, "/")
      |> Map.put(:remote_ip, @traefik)
      |> put_req_header("x-forwarded-for", @cf_edge)
      |> put_req_header("cf-connecting-ip", @client)
      |> ClientIp.call([])

    assert conn.remote_ip == parse(@client)
    assert Logger.metadata()[:remote_ip] == @client
  end

  defp parse(ip) do
    {:ok, ip} = ip |> String.to_charlist() |> :inet.parse_address()
    ip
  end
end
