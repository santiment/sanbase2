defmodule SanbaseWeb.LiveViewUtils do
  @moduledoc false
  alias Sanbase.Utils.Config
  alias SanbaseWeb.Plug.SessionPlug

  def session_options(opts) do
    opts
    |> Keyword.put(:domain, Config.module_get(SessionPlug, :domain))
    |> Keyword.put(:key, Config.module_get(SessionPlug, :session_key))
  end
end
