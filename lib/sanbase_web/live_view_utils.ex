defmodule SanbaseWeb.LiveViewUtils do
  require Sanbase.Utils.Config, as: Config

  def session_options(opts) do
    opts
    |> Keyword.put(:domain, Config.module_get(SanbaseWeb.Plug.SessionPlug, :domain))
    |> Keyword.put(:key, Config.module_get(SanbaseWeb.Plug.SessionPlug, :session_key))
  end
end
