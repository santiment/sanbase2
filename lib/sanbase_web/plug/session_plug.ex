defmodule SanbaseWeb.Plug.SessionPlug do
  @moduledoc ~s"""
  Wraps `Plug.Sesson` plug so it can be configured with runtime opts.
  """

  @behaviour Plug

  alias Sanbase.Utils.Config

  def init(opts), do: opts

  def call(conn, opts) do
    runtime_opts =
      opts
      |> Keyword.put(:domain, Config.module_get(__MODULE__, :domain))
      |> Keyword.put(:key, Config.module_get(__MODULE__, :session_key))
      |> Plug.Session.init()

    Plug.Session.call(conn, runtime_opts)
  end
end
