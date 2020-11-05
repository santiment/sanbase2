defmodule Sanbase.Utils.Conn do
  def put_extra_resp_headers(conn, []), do: conn

  def put_extra_resp_hedears(conn, [{key, value} | rest]) do
    Plug.Conn.put_resp_header(conn, key, value)
    |> put_extra_resp_headers(rest)
  end
end
