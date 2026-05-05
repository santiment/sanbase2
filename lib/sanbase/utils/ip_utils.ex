defmodule Sanbase.Utils.IP do
  @range100mask10 CIDR.parse("100.64.0.0/10")
  @range10mask8 CIDR.parse("10.0.0.0/8")

  @blocked_hostnames ~w(localhost)

  def san_cluster_ip?("::ffff:" <> rest), do: san_cluster_ip?(rest)

  def san_cluster_ip?(remote_ip) do
    with {:ok, false} <- CIDR.match(@range100mask10, remote_ip),
         {:ok, false} <- CIDR.match(@range10mask8, remote_ip) do
      false
    else
      {:ok, true} -> true
      {:error, _} -> false
    end
  end

  def localhost?("127.0.0.1"), do: true
  def localhost?("0.0.0.0"), do: true
  def localhost?("::1"), do: true
  def localhost?("0:0:0:0:0:0:0:1"), do: true
  def localhost?(_), do: false

  def ip_tuple_to_string(ip), do: ip |> :inet_parse.ntoa() |> to_string()

  @doc ~s"""
  Returns `true` when the host is private, reserved, loopback, link-local,
  multicast, broadcast, or a known cloud-metadata endpoint. Use this when
  validating user-supplied URLs to prevent SSRF (e.g. webhook destinations
  pointing at `http://169.254.169.254/`).

  Accepts a hostname string, an IP literal string, or an `:inet.ip_address/0`
  tuple.
  """
  def blocked_host?(host) when is_binary(host) do
    h = String.downcase(host)

    cond do
      h in @blocked_hostnames ->
        true

      String.ends_with?(h, ".localhost") ->
        true

      true ->
        case :inet.parse_address(to_charlist(h)) do
          {:ok, addr} -> private_or_reserved?(addr)
          {:error, _} -> false
        end
    end
  end

  def blocked_host?(addr) when is_tuple(addr), do: private_or_reserved?(addr)

  @doc ~s"""
  Returns `true` for IPv4 / IPv6 addresses in private, reserved, loopback,
  link-local, multicast or broadcast ranges (including IPv4-mapped IPv6
  forms of those ranges).
  """
  # IPv4
  def private_or_reserved?({0, _, _, _}), do: true
  def private_or_reserved?({10, _, _, _}), do: true
  def private_or_reserved?({127, _, _, _}), do: true
  def private_or_reserved?({169, 254, _, _}), do: true
  def private_or_reserved?({172, b, _, _}) when b in 16..31, do: true
  def private_or_reserved?({192, 0, 0, _}), do: true
  def private_or_reserved?({192, 168, _, _}), do: true
  def private_or_reserved?({100, b, _, _}) when b in 64..127, do: true
  def private_or_reserved?({a, _, _, _}) when a >= 224, do: true

  # IPv6 unspecified, loopback, link-local (fe80::/10), unique-local (fc00::/7)
  def private_or_reserved?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  def private_or_reserved?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def private_or_reserved?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true
  def private_or_reserved?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true

  # IPv4-mapped IPv6: ::ffff:a.b.c.d
  def private_or_reserved?({0, 0, 0, 0, 0, 0xFFFF, ab, cd}),
    do: private_or_reserved?({div(ab, 256), rem(ab, 256), div(cd, 256), rem(cd, 256)})

  def private_or_reserved?(_), do: false
end
