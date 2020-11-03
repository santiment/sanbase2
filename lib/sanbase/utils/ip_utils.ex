defmodule Sanbase.Utils.IP do
  def is_san_cluster_ip?(remote_ip) do
    cidr = CIDR.parse("100.64.0.0/10")

    case CIDR.match(cidr, remote_ip) do
      {:ok, boolean} -> boolean
      _ -> false
    end
  end

  def is_localhost?("127.0.0.1"), do: true
  def is_localhost?("0.0.0.0"), do: true
  def is_localhost?("::1"), do: true
  def is_localhost?("0:0:0:0:0:0:0:1"), do: true
  def is_localhost?(_), do: false
end
