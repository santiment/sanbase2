import Config

if config_env() in [:dev, :test] do
  # In order to properly work while developing locally,
  # load the .env file before doing the configuration
  Code.ensure_loaded?(Envy) && Envy.auto_load()
end

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Twitter.OAuth,
  consumer_key: System.get_env("TWITTER_OAUTH_CONSUMER_KEY"),
  consumer_secret: System.get_env("TWITTER_OAUTH_CONSUMER_SECRET")

config :sanbase, Sanbase.TemplateMailer,
  adapter: Swoosh.Adapters.Mailjet,
  api_key: System.get_env("MAILJET_API_KEY"),
  secret: System.get_env("MAILJET_API_SECRET")

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")
  parity_url = System.get_env("PARITY_URL")

  config :sanbase2, SanbaseWeb.Endpoint,
    url: [host: host, port: port],
    http: [
      port: port,
      protocol_options: [
        max_header_name_length: 64,
        max_header_value_length: 8192,
        max_request_line_length: 16_384,
        max_headers: 100
      ]
    ],
    secret_key_base: secret_key_base,
    server: true,
    cache_static_manifest: "priv/static/cache_manifest.json",
    root: ".",
    version: Application.spec(:sanbase, :vsn),
    load_from_system_env: true,
    check_origin: [
      "//*.santiment.net",
      "//*.sanr.app",
      "//*.sanbase-admin.stage.san",
      "//*.sanbase-admin.production.san"
    ]

  config :ethereumex,
    url: parity_url,
    http_options: [timeout: 25_000, recv_timeout: 25_000],
    http_headers: [{"Content-Type", "application/json"}]

  git_commit = System.get_env("GIT_COMMIT")

  config :sentry,
    release: "sanbase:#{git_commit}",
    dsn: System.get_env("SENTRY_DSN"),
    environment_name: :prod,
    enable_source_code_context: true,
    root_source_code_path: File.cwd!(),
    tags: %{
      env: "production"
    }
end
