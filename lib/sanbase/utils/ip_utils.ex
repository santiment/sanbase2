defmodule Sanbase.Utils.IP do
  @range100mask10 CIDR.parse("100.64.0.0/10")
  @range10mask8 CIDR.parse("10.0.0.0/8")

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
end
