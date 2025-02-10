import Config

if config_env() in [:dev, :test] do
  # In order to properly work while developing locally,
  # load the .env file before doing the configuration
  Code.ensure_loaded?(Envy) && Envy.auto_load()
end

kafka_url = System.get_env("KAFKA_URL", "blockchain-kafka-kafka")
kafka_port = System.get_env("KAFKA_PORT", "9092")
kafka_enabled = System.get_env("REAL_KAFKA_ENABLED", "true")

kafka_endpoints =
  if kafka_enabled == "true" do
    # Locally KAFKA_PORT can be '30911, 30912, 30913'
    kafka_port
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn port ->
      {kafka_url, String.to_integer(port)}
    end)
  else
    []
  end

config :brod,
  clients: [
    kafka_client: [
      endpoints: kafka_endpoints,
      auto_start_producers: true
    ]
  ]

config :sanbase, Sanbase.SmartContracts.SanrNFT, alchemy_api_key: System.get_env("ALCHEMY_API_KEY")

config :sanbase, Sanbase.TemplateMailer,
  adapter: Swoosh.Adapters.Mailjet,
  api_key: System.get_env("MAILJET_API_KEY"),
  secret: System.get_env("MAILJET_API_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Twitter.OAuth,
  consumer_key: System.get_env("TWITTER_OAUTH_CONSUMER_KEY"),
  consumer_secret: System.get_env("TWITTER_OAUTH_CONSUMER_SECRET")

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

  db_url = System.get_env("DATABASE_URL")
  uri = URI.parse(db_url)
  [username, password] = String.split(uri.userinfo, ":")
  database = db_url |> String.split("/") |> List.last()
  git_commit = System.get_env("GIT_COMMIT")

  config :ethereumex,
    url: parity_url,
    http_options: [timeout: 25_000, recv_timeout: 25_000],
    http_headers: [{"Content-Type", "application/json"}]

  config :libcluster,
    topologies: [
      postgres_topology: [
        strategy: LibclusterPostgres.Strategy,
        config: [
          hostname: uri.host,
          username: username,
          password: password,
          database: database,
          port: 5432,
          parameters: [],
          ssl: true,
          ssl_opts: [verify: :verify_none],
          channel_name: "sanbase_cluster"
        ]
      ]
    ]

  config :sanbase, Sanbase.Metric.Registry.Sync, sync_secret: System.get_env("METRIC_REGISTRY_SYNC_SECRET")

  config :sanbase, Sanbase.Repo,
    ssl: true,
    ssl_opts: [verify: :verify_none]

  config :sanbase, SanbaseWeb.Endpoint,
    url: [host: host, port: port],
    http: [
      :inet6,
      port: port,
      protocol_options: [
        max_header_name_length: 64,
        max_header_value_length: 8192,
        max_request_line_length: 16_384,
        max_headers: 100,
        idle_timeout: 100_000
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
      "//*.sanitize.page",
      "//*.sanbase-admin.stage.san",
      "//*.sanbase-admin.production.san"
    ]

  config :sentry,
    release: "sanbase:#{git_commit}",
    dsn: System.get_env("SENTRY_DSN"),
    environment_name: :prod,
    enable_source_code_context: true,
    root_source_code_path: File.cwd!(),
    tags: %{
      env: "production"
    },
    integrations: [
      oban: [
        # Capture errors:
        capture_errors: true,
        # Monitor cron jobs:
        cron: [enabled: true]
      ]
    ]
end
