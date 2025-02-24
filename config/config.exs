import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --external:/js/* --external:/css/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.1",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Latest version of timezone data (2019a) distributed by IANA has an error
# Disable the autoupdate until it is fixed
config :tzdata, :autoupdate, :disabled

config :ethereumex,
  url: "https://ethereum.santiment.net",
  http_options: [timeout: 25_000, recv_timeout: 25_000],
  http_headers: [{"Content-Type", "application/json"}]

config :event_bus,
  # Otherwise the `Base62` is reported as undefined
  id_generator: EventBus.Util.Base62

# General application configuration
config :sanbase,
  env: Mix.env(),
  ecto_repos: [Sanbase.Repo],
  available_slugs_module: Sanbase.AvailableSlugs

config :sanbase, Sanbase.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

config :phoenix, :json_library, Jason

config :postgrex, :json_library, Jason

config :sanbase, Sanbase,
  # will be stage or prod
  deployment_env: {:system, "DEPLOYMENT_ENVIRONMENT", "dev"},
  env: Mix.env()

config :sanbase, SanbaseWeb.Plug.BasicAuth,
  username: {:system, "ADMIN_BASIC_AUTH_USERNAME", "admin"},
  password: {:system, "ADMIN_BASIC_AUTH_PASSWORD", "admin"}

config :sanbase, Sanbase.RepoReader,
  projects_data_endpoint_secret: {:system, "PROJECTS_DATA_ENDPOINT_SECRET"}

config :sanbase, Sanbase.Price.Validator, enabled: {:system, "PRICE_VALIDATOR_ENABLED", true}

config :sanbase, Sanbase.Cryptocompare, api_key: {:system, "CRYPTOCOMPARE_API_KEY"}

config :sanbase, Sanbase.Kafka,
  kafka_url: {:system, "KAFKA_URL", "blockchain-kafka-kafka"},
  kafka_port: {:system, "KAFKA_PORT", "9092"}

config :sanbase, Sanbase.KafkaExporter,
  producer: Sanbase.Kafka.Implementation.Producer,
  kafka_url: {:system, "KAFKA_URL", "blockchain-kafka-kafka"},
  kafka_port: {:system, "KAFKA_PORT", "9092"},
  prices_topic: {:system, "KAFKA_PRICES_TOPIC", "asset_prices"},
  asset_price_pairs_topic: {:system, "KAFKA_CRYPTOCOMPARE_PRICES_TOPIC", "asset_price_pairs"},
  asset_price_pairs_only_topic:
    {:system, "KAFKA_CRYPTOCOMPARE_PRICES_ONLY_TOPIC", "asset_price_pairs_only"},
  open_interest_topic: {:system, "KAFKA_OPEN_INTEREST_TOPIC", "open_interest_cryptocompare"},
  open_interest_topic_v2:
    {:system, "KAFKA_OPEN_INTEREST_TOPIC_V2", "open_interest_cryptocompare_v2"},
  funding_rate_topic: {:system, "KAFKA_FUNDING_RATE_TOPIC", "funding_rate_cryptocompare"},
  api_call_data_topic: {:system, "KAFKA_API_CALL_DATA_TOPIC", "sanbase_api_call_data"},
  twitter_followers_topic: {:system, "KAFKA_TWITTER_FOLLOWERS_TOPIC", "twitter_followers"}

config :sanbase, Sanbase.EventBus.KafkaExporterSubscriber,
  event_bus_topic: {:system, "KAFKA_EVENT_BUS_TOPIC", "sanbase_event_bus"},
  buffering_max_messages: 250,
  can_send_after_interval: 1000,
  kafka_flush_timeout: 5000

config :sanbase, Sanbase.ExternalServices.RateLimiting.Server,
  implementation_module: Sanbase.ExternalServices.RateLimiting.WaitServer

config :sanbase, Sanbase.ClickhouseRepo,
  adapter: Ecto.Adapters.Postgres,
  queue_target: 10_000,
  queue_interval: 2000,
  max_overflow: 3,
  scheme: :http

clickhouse_read_only_opts = [
  adapter: Ecto.Adapters.Postgres,
  queue_target: 60_000,
  queue_interval: 60_000,
  max_overflow: 3,
  scheme: :http
]

config :sanbase, Sanbase.ClickhouseRepo.ReadOnly, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.FreeUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseMaxUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessMaxUser, clickhouse_read_only_opts

config :sanbase, Sanbase.Repo,
  loggers: [Ecto.LogEntry],
  adapter: Ecto.Adapters.Postgres,
  pool_size: {:system, "SANBASE_POOL_SIZE", "20"},
  max_overflow: 5,
  queue_target: 5000,
  queue_interval: 1000,
  timeout: 30_000,
  migration_timestamps: [type: :naive_datetime_usec]

config :sanbase, Sanbase.Accounts.Hmac, secret_key: {:system, "APIKEY_HMAC_SECRET_KEY", nil}

# Configures the endpoint
config :sanbase, SanbaseWeb.Endpoint,
  http: [protocol_options: [max_request_line_length: 16_384, max_header_value_length: 8192]],
  url: [host: "localhost"],
  secret_key_base:
    "not_secret_please_do_not_report_Vq7Rfo0T4EfiLX2/ryYal3O0l9ebBNhyh58cfWdTAUHxEJGu2p9u1WTQ31Ki4Phj",
  render_errors: [view: SanbaseWeb.ErrorView, accepts: ~w(json)],
  server: true,
  # should be removed after app.santiment.net migration
  website_url: {:system, "WEBSITE_URL", "http://localhost:4000"},
  backend_url: {:system, "BACKEND_URL", "http://localhost:4000"},
  admin_url: {:system, "ADMIN_URL", "http://localhost:4000"},
  frontend_url: {:system, "FRONTEND_URL", "https://app-stage.santiment.net"},
  insights_url: {:system, "INSIGHTS_URL", "https://insights.santiment.net"},
  pubsub_server: Sanbase.PubSub,
  live_view: [signing_salt: "not_secret_please_do_not_report_FkOgrxfW5aw3HjLOoxCVMvB0py5+Uk5+"]

# Do not log SASL crash reports
config :sasl, sasl_error_logger: false

# Configures Elixir's Logger
config :logger, :console,
  format: {Sanbase.Utils.JsonLogger, :format},
  metadata: [:request_id, :api_token, :user_id, :remote_ip, :complexity, :query, :san_balance],
  handle_otp_reports: true,
  handle_sasl_reports: true

# Error tracking
config :sentry,
  json_library: Jason,
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  integrations: [
    oban: [
      # Capture errors:
      capture_errors: true,
      # Monitor cron jobs:
      cron: [enabled: true]
    ]
  ]

config :earmark,
  # disable using parallel map die to timeout errors
  timeout: nil,
  mapper: &Enum.map/2

config :hammer,
  backend: {
    Hammer.Backend.ETS,
    [
      expiry_ms: 60_000 * 60 * 4,
      cleanup_interval_ms: 60_000 * 10
    ]
  }

config :tesla,
  adapter: {Tesla.Adapter.Hackney, recv_timeout: 30_000}

config :sanbase, Sanbase.ApiCallLimit,
  quota_size: 100,
  quota_size_max_offset: 100

config :sanbase, Sanbase.InternalServices.Ethauth,
  url: {:system, "ETHAUTH_URL"},
  basic_auth_username: {:system, "ETHAUTH_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "ETHAUTH_BASIC_AUTH_PASSWORD"}

config :sanbase, Sanbase.InternalServices.Parity,
  url: {:system, "PARITY_URL"},
  basic_auth_username: {:system, "PARITY_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "PARITY_BASIC_AUTH_PASSWORD"}

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  rate_limiting_enabled: {:system, "SANBASE_API_CALL_RATE_LIMITING_ENABLED", true}

config :sanbase, SanbaseWeb.Graphql.AuthPlug,
  basic_auth_username: {:system, "GRAPHQL_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "GRAPHQL_BASIC_AUTH_PASSWORD"}

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "eu-central-1"

config :sanbase, Sanbase.SimpleMailer,
  adapter: Swoosh.Adapters.AmazonSES,
  region: "eu-west-1",
  access_key: {:system, "AWS_SES_ACCESS_KEY_ID"},
  secret: {:system, "AWS_SES_SECRET_ACCESS_KEY"}

config :sanbase, Sanbase.PresignedS3Url.S3,
  access_key_id: {:system, "AWS_USER_DATASETS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_USER_DATASETS_SECRET_ACCESS_KEY"}

config :sanbase, Sanbase.Cryptocompare, api_key: {:system, "CRYPTOCOMPARE_API_KEY"}

config :sanbase, Sanbase.TechIndicators, url: {:system, "TECH_INDICATORS_URL"}

config :sanbase, Sanbase.SocialData,
  metricshub_url: {:system, "METRICS_HUB_URL", "http://metrics-hub-server"}

config :waffle,
  storage: Waffle.Storage.S3,
  # To support AWS regions other than US Standard
  virtual_host: true,
  bucket: {:system, "POSTS_IMAGE_BUCKET"}

config :sanbase, SanbaseWeb.Graphql.Middlewares.AccessControl,
  restrict_to_in_days: {:system, "RESTRICT_TO_IN_DAYS", "1"},
  restrict_from_in_days: {:system, "RESTRICT_FROM_IN_MONTHS", "90"}

config :sanbase, Sanbase.MetricExporter.S3, bucket: {:system, "METRICS_EXPORTER_S3_BUCKET"}

config :libcluster,
  topologies: [
    postgres_topology: [
      strategy: LibclusterPostgres.Strategy,
      config: [
        hostname: "localhost",
        username: "postgres",
        password: "postgres",
        database: "sanbase_dev",
        port: 5432,
        parameters: [],
        ssl: false,
        ssl_opts: nil,
        channel_name: "sanbase_cluster"
      ]
    ]
  ]

config :sanbase, SanbaseWeb.Plug.SessionPlug,
  domain: {:system, "SANTIMENT_ROOT_DOMAIN", "localhost"},
  session_key: {:system, "SESSION_KEY", "_sanbase_sid"}

config :sanbase, SanbaseWeb.Plug.BotLoginPlug,
  bot_login_endpoint: {:system, "BOT_LOGIN_SECRET_ENDPOINT"}

config :sanbase, Sanbase.Intercom, api_key: {:system, "INTERCOM_API_KEY"}

config :sanbase, Sanbase.Affiliate.FirstPromoterApi,
  api_id: {:system, "FIRST_PROMOTER_API_ID"},
  api_key: {:system, "FIRST_PROMOTER_API_KEY"}

config :sanbase, Oban.Web,
  repo: Sanbase.Repo,
  queues: [
    email_queue: 5,
    refresh_queries: 1,
    notifications_queue: 1,
    reminder_notifications_queue: 1
  ],
  name: :oban_web

config :sanbase, Oban.Admin,
  repo: Sanbase.Repo,
  queues: [],
  name: :oban_admin

config :nostrum,
  token: {:system, "DISCORD_BOT_QUERY_TOKEN"},
  gateway_intents: [
    :guilds,
    :guild_members,
    :direct_messages,
    :guild_messages,
    :message_content
  ]

config :ex_audit,
  ecto_repos: [Sanbase.Repo],
  version_schema: Sanbase.Version,
  tracked_schemas: [
    Sanbase.Project,
    Sanbase.Metric.Registry
  ],
  primitive_structs: [DateTime, NaiveDateTime, Date]

config :sanbase, Sanbase.Metric.Registry.Sync, sync_secret: "secret_only_on_prod"

# Import configs
import_config "ueberauth_config.exs"
import_config "scrapers_config.exs"
import_config "notifications_config.exs"
import_config "stripe_config.exs"
import_config "scheduler_config.exs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
