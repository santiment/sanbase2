defmodule SanbaseWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sanbase
  use SanbaseWeb.Endpoint.ErrorHandler

  require Sanbase.Utils.Config, as: Config

  socket("/socket", SanbaseWeb.UserSocket,
    # or list of options
    websocket: true,
    longpoll: [check_origin: Phoenix.Transports.LongPoll]
  )

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

  plug(SanbaseWeb.Plug.SessionPlug,
    store: :cookie,
    # 30 days
    max_age: 24 * 60 * 60 * 30,
    key: "_sanbase_sid",
    # Doesn't need to be a secret. Session cookies are signed by both secret_key_base and signing_salt
    # For reference: https://github.com/phoenixframework/phoenix/issues/2146
    signing_salt: "grT-As16"
  )

  plug(Corsica,
    origins: [
      "https://app-stage.santiment.net/",
      "https://neuro-stage.santiment.net/",
      "https://app.santiment.net/",
      "httsp://neuro.santiment.net"
    ],
    allow_credentials: true
  )

  # makes the /metrics URL happen
  plug(Sanbase.Prometheus.Exporter)

  # measures pipeline exec times
  plug(Sanbase.Prometheus.PipelineInstrumenter)

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

  def sonar_url() do
    website_url()
    |> Path.join("sonar")
  end

  def historical_balance_url(address, asset) when is_binary(address) and is_binary(asset) do
    website_url()
    |> Path.join("/labs/balance")
    |> Path.join(URI.encode_query("assets[]": asset, address: address))
  end

  def user_account_url() do
    Config.get(:website_url)
    |> Path.join("account")
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

  def login_url(token, email, nil) do
    frontend_url() <> "/email_login?" <> URI.encode_query(token: token, email: email)
  end

  def login_url(token, email, origin_url) do
    origin_url <> "/email_login?" <> URI.encode_query(token: token, email: email)
  end

  def verify_url(email_candidate_token, email_candidate) do
    frontend_url() <>
      "/verify_email?" <>
      URI.encode_query(token: email_candidate_token, emailCandidate: email_candidate)
  end
end
