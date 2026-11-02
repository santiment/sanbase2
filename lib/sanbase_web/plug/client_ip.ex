defmodule SanbaseWeb.Plug.ClientIp do
  @moduledoc ~s"""
  Set `conn.remote_ip` to the real client IP for requests that come through
  Cloudflare.

  Requests reach the app as client -> Cloudflare -> Traefik -> Phoenix. With
  the default `RemoteIp` settings the Cloudflare edge address was taken as the
  client, so every per-IP limit and every logged IP was really Cloudflare's.

  How the client IP is found:
    1. Take the nearest hop from the forwarding headers that is not private or
       loopback (`RemoteIp` defaults).

       In-cluster addresses (100.64.0.0/10) are deliberately not skipped: an
       in-cluster service that calls the API keeps its own address as the
       client, and `Sanbase.ApiCallLimit` exempts cluster addresses from limits
       (`Sanbase.Utils.IP.san_cluster_ip?/1`). That is how it worked before.
    2. If that hop is a Cloudflare address, the request came through Cloudflare,
       so its `CF-Connecting-IP` header is trusted. Cloudflare always sets that
       header itself and replaces any value the client sent.
    3. Otherwise the request did not come through Cloudflare (for example a
       direct call to the load balancer). Its `CF-Connecting-IP` header is
       ignored, because anyone can send it, and the nearest hop is the client.

  If `CF-Connecting-IP` is missing or invalid on a Cloudflare request, the
  `X-Forwarded-For` chain is read with the Cloudflare ranges as trusted proxies.

  Must run before anything that reads `conn.remote_ip`, so it is plugged in the
  endpoint, right after `Plug.RequestId`.
  """

  @behaviour Plug

  import Bitwise

  require Logger

  # Published at https://www.cloudflare.com/ips/ (checked 2026-11-02).
  @cloudflare_ranges ~w[
    173.245.48.0/20
    103.21.244.0/22
    103.22.200.0/22
    103.31.4.0/22
    141.101.64.0/18
    108.162.192.0/18
    190.93.240.0/20
    188.114.96.0/20
    197.234.240.0/22
    198.41.128.0/17
    162.158.0.0/15
    104.16.0.0/13
    104.24.0.0/14
    172.64.0.0/13
    131.0.72.0/22
    2400:cb00::/32
    2606:4700::/32
    2803:f800::/32
    2405:b500::/32
    2405:8100::/32
    2a06:98c0::/29
    2c0f:f248::/32
  ]

  # {tuple size, network as integer, prefix bits}, computed once at compile time.
  @cloudflare_blocks (for cidr <- @cloudflare_ranges do
                        [address, bits] = String.split(cidr, "/")
                        {:ok, ip} = :inet.parse_address(String.to_charlist(address))
                        step = if tuple_size(ip) == 4, do: 8, else: 16

                        value =
                          ip |> Tuple.to_list() |> Enum.reduce(0, &((&2 <<< step) + &1))

                        {tuple_size(ip), value, String.to_integer(bits)}
                      end)

  def cloudflare_ranges(), do: @cloudflare_ranges

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ip = client_ip(conn.req_headers, conn.remote_ip)

    case :inet.ntoa(ip) do
      {:error, _} -> :ok
      ip_string -> Logger.metadata(remote_ip: to_string(ip_string))
    end

    %{conn | remote_ip: ip}
  end

  @doc false
  def client_ip(headers, peer_ip) do
    case RemoteIp.from(headers) do
      nil ->
        peer_ip

      nearest_hop ->
        if cloudflare?(nearest_hop) do
          cf_connecting_ip(headers) ||
            RemoteIp.from(headers, proxies: @cloudflare_ranges) ||
            nearest_hop
        else
          nearest_hop
        end
    end
  end

  @doc ~s"""
  Whether `ip` (an `:inet` tuple) is in one of Cloudflare's published ranges.
  """
  @spec cloudflare?(:inet.ip_address()) :: boolean()
  def cloudflare?(ip) when is_tuple(ip) do
    size = tuple_size(ip)
    value = ip_to_integer(ip)
    total_bits = if size == 4, do: 32, else: 128

    Enum.any?(@cloudflare_blocks, fn {block_size, net, bits} ->
      block_size == size and value >>> (total_bits - bits) == net >>> (total_bits - bits)
    end)
  end

  defp cf_connecting_ip(headers) do
    with {_, value} <- List.keyfind(headers, "cf-connecting-ip", 0),
         {:ok, ip} <- value |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
      ip
    else
      _ -> nil
    end
  end

  defp ip_to_integer(ip) do
    step = if tuple_size(ip) == 4, do: 8, else: 16
    ip |> Tuple.to_list() |> Enum.reduce(0, &((&2 <<< step) + &1))
  end
end
