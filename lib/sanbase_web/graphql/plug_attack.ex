defmodule SanbaseWeb.Graphql.PlugAttack do
  use PlugAttack
  import Plug.Conn
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  rule "allow local", conn do
    allow(conn.remote_ip == {127, 0, 0, 1})
  end

  rule "throttle per ip", conn do
    throttle(
      conn.remote_ip,
      period: Config.get(:rate_limit_period) |> String.to_integer(),
      limit: Config.get(:rate_limit_max_requests) |> String.to_integer(),
      storage: {PlugAttack.Storage.Ets, SanbaseWeb.Graphql.PlugAttack.Storage}
    )
  end

  def allow_action(conn, {:throttle, data}, opts) do
    conn
    |> add_throttling_headers(data)
    |> allow_action(true, opts)
  end

  def allow_action(conn, _data, _opts) do
    conn
  end

  def block_action(conn, {:throttle, data}, opts) do
    conn
    |> add_throttling_headers(data)
    |> block_action(false, opts)
  end

  def block_action(conn, _data, _opts) do
    conn
    |> send_resp(:forbidden, "Forbidden\n")
    |> halt
  end

  defp add_throttling_headers(conn, data) do
    # The expires_at value is a unix time in milliseconds, we want to return one
    # in seconds
    reset = div(data[:expires_at], 1_000)

    conn
    |> put_resp_header("x-ratelimit-limit", to_string(data[:limit]))
    |> put_resp_header("x-ratelimit-remaining", to_string(data[:remaining]))
    |> put_resp_header("x-ratelimit-reset", to_string(reset))
  end
end
