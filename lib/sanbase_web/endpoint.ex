defmodule SanbaseWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sanbase
  require Sanbase.Utils.Config, as: Config

  socket("/socket", SanbaseWeb.UserSocket)

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(Plug.Static, at: "/", from: :sanbase, gzip: false)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(
    Plug.Session,
    store: :cookie,
    key: "_sanbase_key",
    signing_salt: "bfH+5EQ0"
  )

  if Mix.env() == :dev do
    plug(Corsica, origins: ["http://localhost:3000", "http://0.0.0.0:4000"])
  end

  plug(SanbaseWeb.Router)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end

  def website_url() do
    Config.get(:website_url)
  end

  def frontend_url() do
    Config.get(:frontend_url)
  end

  def backend_url() do
    Config.get(:backend_url)
  end

  def api_url() do
    backend_url() <> "/graphql"
  end

  def login_url(token, email) do
    frontend_url() <> "/email_login?" <> URI.encode_query(token: token, email: email)
  end
end
