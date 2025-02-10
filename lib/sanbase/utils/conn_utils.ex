defmodule Sanbase.Utils.Conn do
  @moduledoc false
  def put_extra_resp_headers(conn, []), do: conn

  def put_extra_resp_headers(conn, [{key, value} | rest]) do
    conn
    |> Plug.Conn.put_resp_header(key, to_string(value))
    |> put_extra_resp_headers(rest)
  end

  def put_extra_req_headers(conn, []), do: conn

  def put_extra_req_headers(conn, [{key, value} | rest]) do
    conn
    |> Plug.Conn.put_req_header(key, to_string(value))
    |> put_extra_req_headers(rest)
  end
end
