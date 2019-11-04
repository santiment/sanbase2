defmodule SanbaseWeb.Plug.SessionPlug do
  @moduledoc ~s"""
  Wraps `Plug.Sesson` plug so it can be configured with runtime opts.
  """

  @behaviour Plug

  require Sanbase.Utils.Config, as: Config

  def init(opts) do
    IO.inspect(" I AM BEING CALLED")
    opts
  end

  def call(conn, opts) do
    runtime_opts =
      opts
      |> Keyword.put(:domain, Config.get(:domain))
      |> Keyword.put(:key, Config.get(:session_key))
      |> Plug.Session.init()

    Plug.Session.call(conn, runtime_opts)
  end
end
