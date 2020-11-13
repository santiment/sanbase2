defmodule Sanbase.Utils.Conn do
  def put_extra_resp_headers(conn, []), do: conn

  def put_extra_resp_headers(conn, [{key, value} | rest]) do
    Plug.Conn.put_resp_header(conn, key, to_string(value))
    |> put_extra_resp_headers(rest)
  end

  def put_extra_req_headers(conn, []), do: conn

  def put_extra_req_headers(conn, [{key, value} | rest]) do
    Plug.Conn.put_req_header(conn, key, to_string(value))
    |> put_extra_req_headers(rest)
  end
end
