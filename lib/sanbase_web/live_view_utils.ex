defmodule SanbaseWeb.LiveViewUtils do
  alias Sanbase.Utils.Config

  def session_options(opts) do
    opts
    |> Keyword.put(:domain, Config.module_get(SanbaseWeb.Plug.SessionPlug, :domain))
    |> Keyword.put(:key, Config.module_get(SanbaseWeb.Plug.SessionPlug, :session_key))
  end
end
