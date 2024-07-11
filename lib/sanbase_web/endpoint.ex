defmodule SanbaseWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :sanbase
  use SanbaseWeb.Endpoint.ErrorHandler
  use Absinthe.Phoenix.Endpoint

  alias Sanbase.Utils.Config

  @session_options [
    store: :cookie,
    # 30 days
    max_age: 24 * 60 * 60 * 30,
    # Doesn't need to be a secret. Session cookies are signed by both secret_key_base and signing_salt
    # For reference: https://github.com/phoenixframework/phoenix/issues/2146
    signing_salt: "grT-As16"
  ]

  socket("/socket", SanbaseWeb.UserSocket, websocket: true, check_origin: false)

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [
        session: {SanbaseWeb.LiveViewUtils, :session_options, [@session_options]}
      ]
    ],
    check_origin: false
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :sanbase,
    gzip: false,
    only: SanbaseWeb.static_paths()
  )

  # Prometheus /metrics endpoint
  plug(PromEx.Plug, prom_ex_module: SanbaseWeb.Prometheus)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)

  # This plug should be placed before Plug.Parsers because it is reading the
  # request body and it can be read only once and if used anywhere else should be stored
  plug(SanbaseWeb.Plug.VerifyStripeWebhook)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Sentry.PlugContext)

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # Some things are configured at runtime in SanbaseWeb.Plug.SessionPlug.call
  plug(SanbaseWeb.Plug.SessionPlug, @session_options)

  plug(SanbaseWeb.Router)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"

      {:ok,
       Keyword.put(config, :http, [
         :inet6,
         port: port,
         protocol_options: [
           max_header_name_length: 64,
           max_header_value_length: 8192,
           max_request_line_length: 16_384,
           max_headers: 100,
           idle_timeout: 100_000
         ]
       ])}
    else
      {:ok, config}
    end
  end

  def website_url() do
    Config.module_get(__MODULE__, :website_url)
  end

  def project_url(slug) when is_binary(slug) do
    Path.join([frontend_url(), "charts?slug=#{slug}"])
  end

  def sonar_url() do
    website_url()
    |> Path.join("alerts")
  end

  def my_alerts_url() do
    sonar_url()
    |> Path.join("my-alerts")
  end

  def trending_word_url(word) when is_binary(word) do
    website_url()
    |> Path.join("labs/trends/explore")
    |> Path.join(word)
  end

  def trending_word_url(words) when is_list(words) do
    words_uri = words |> Enum.map(&~s/"#{&1}"/) |> Enum.join(" OR ") |> URI.encode()

    website_url()
    |> Path.join("labs/trends/explore")
    |> Path.join(words_uri)
  end

  def historical_balance_url(address, asset) when is_binary(address) and is_binary(asset) do
    website_url()
    |> Path.join("/labs/balance")
    |> Path.join("?" <> URI.encode_query("assets[]": asset, address: address))
  end

  def historical_balance_url(address, asset) do
    frontend_url() <> "/labs/balance?address=#{address}&assets[]=#{asset}"
  end

  def feed_url() do
    Config.module_get(__MODULE__, :website_url)
    |> Path.join("feed")
  end

  def user_account_url() do
    Config.module_get(__MODULE__, :website_url)
    |> Path.join("account")
  end

  def frontend_url() do
    Config.module_get(__MODULE__, :frontend_url)
  end

  def backend_url() do
    Config.module_get(__MODULE__, :backend_url)
  end

  def api_url() do
    backend_url() <> "/graphql"
  end

  def verify_url(email_candidate_token, email_candidate) do
    frontend_url() <>
      "/verify_email?" <>
      URI.encode_query(token: email_candidate_token, emailCandidate: email_candidate)
  end

  def show_alert_url(id) do
    sonar_url() <> "/#{id}"
  end

  def trending_words_datetime_url(datetime_iso) do
    frontend_url() <> "/labs/trends?datetime=#{datetime_iso}"
  end
end
