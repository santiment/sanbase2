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
      |> Keyword.put(:domain, cookie_domain())
      |> Keyword.put(:key, Config.module_get(__MODULE__, :session_key))
      |> Keyword.put(:same_site, "Lax")
      |> Keyword.put(:secure, secure_cookie?())
      |> Keyword.put(:http_only, true)
      |> Plug.Session.init()

    Plug.Session.call(conn, runtime_opts)
  end

  # Locally (dev/test) the session cookie is host-only (no Domain attribute), so
  # the session — and the CSRF token stored in it — works on whichever host the
  # app is opened through: localhost:4000, 127.0.0.1:4000 or an /etc/hosts alias
  # such as sanbase-admin.stage.san:4000. A Domain that does not match the host
  # makes the browser drop the cookie, and the admin LiveViews then reload in a
  # loop. Deployed envs keep SANTIMENT_ROOT_DOMAIN (set per pod in devops).
  @local_env? Application.compile_env(:sanbase, :env) in [:dev, :test]

  @doc false
  def cookie_domain() do
    if @local_env?, do: nil, else: Config.module_get(__MODULE__, :domain)
  end

  defp secure_cookie?() do
    Config.module_get(Sanbase, :deployment_env) in ["stage", "prod"] and
      Sanbase.ApplicationUtils.container_type() != "admin"
  end
end
