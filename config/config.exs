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
  version: "3.2.7",
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

config :sanbase, Sanbase.Transfers.Erc20Transfers,
  dt_ordered_table: {:system, "DT_ORDERED_ERC20_TRANFERS_TABLE", "erc20_transfers_dt_order"},
  address_ordered_table: {:system, "ADDRESS_ORDERED_ERC20_TRANSFERS_TABLE", "erc20_transfers"}

config :sanbase, Sanbase.Price.Validator, enabled: {:system, "PRICE_VALIDATOR_ENABLED", true}

config :sanbase, Sanbase.Cryptocompare, api_key: {:system, "CRYPTOCOMPARE_API_KEY"}

config :sanbase, Sanbase.Kafka,
  kafka_url: {:system, "KAFKA_URL", "blockchain-kafka-kafka"},
  kafka_port: {:system, "KAFKA_PORT", "9092"}

config :sanbase, Sanbase.KafkaExporter,
  supervisor: SanExporterEx.Producer.Supervisor,
  producer: SanExporterEx.Producer,
  kafka_url: {:system, "KAFKA_URL", "blockchain-kafka-kafka"},
  kafka_port: {:system, "KAFKA_PORT", "9092"},
  prices_topic: {:system, "KAFKA_PRICES_TOPIC", "asset_prices"},
  asset_price_pairs_topic: {:system, "KAFKA_CRYPTOCOMPARE_PRICES_TOPIC", "asset_price_pairs"},
  asset_price_pairs_only_topic:
    {:system, "KAFKA_CRYPTOCOMPARE_PRICES_ONLY_TOPIC", "asset_price_pairs_only"},
  asset_ohlcv_price_pairs_topic:
    {:system, "KAFKA_ASSET_OHLCV_PRICE_POINTS_TOPIC", "asset_ohlcv_price_pairs"},
  open_interest_topic: {:system, "KAFKA_OPEN_INTEREST_TOPIC", "open_interest_cryptocompare"},
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

config :sanbase, Sanbase.ClickhouseRepo.ReadOnly,
  adapter: Ecto.Adapters.Postgres,
  queue_target: 60_000,
  queue_interval: 60_000,
  max_overflow: 3,
  scheme: :http

config :sanbase, Sanbase.Repo,
  loggers: [Ecto.LogEntry],
  adapter: Ecto.Adapters.Postgres,
  pool_size: {:system, "SANBASE_POOL_SIZE", "20"},
  max_overflow: 5,
  queue_target: 5000,
  queue_interval: 1000,
  timeout: 30_000,
  # because of pgbouncer
  prepare: :unnamed,
  migration_timestamps: [type: :naive_datetime_usec]

config :sanbase, Sanbase.Accounts.Hmac, secret_key: {:system, "APIKEY_HMAC_SECRET_KEY", nil}

# Configures the endpoint
config :sanbase, SanbaseWeb.Endpoint,
  http: [protocol_options: [max_request_line_length: 16_384, max_header_value_length: 8192]],
  url: [host: "localhost"],
  secret_key_base: "not_secret_Vq7Rfo0T4EfiLX2/ryYal3O0l9ebBNhyh58cfWdTAUHxEJGu2p9u1WTQ31Ki4Phj",
  render_errors: [view: SanbaseWeb.ErrorView, accepts: ~w(json)],
  # should be removed after app.santiment.net migration
  website_url: {:system, "WEBSITE_URL", "http://localhost:4000"},
  backend_url: {:system, "BACKEND_URL", "http://localhost:4000"},
  frontend_url: {:system, "FRONTEND_URL", "http://localhost:4000"},
  insights_url: {:system, "INSIGHTS_URL", "https://insights.santiment.net"},
  pubsub_server: Sanbase.PubSub,
  live_view: [signing_salt: "not_secret_FkOgrxfW5aw3HjLOoxCVMvB0py5+Uk5+"]

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
  root_source_code_path: File.cwd!()

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

config :xain, :after_callback, {Phoenix.HTML, :raw}

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
    k8s: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "sanbase",
        kubernetes_selector: "app=sanbase",
        polling_interval: 10_000
      ]
    ]
  ]

config :sanbase, SanbaseWeb.Plug.SessionPlug,
  domain: {:system, "SANTIMENT_ROOT_DOMAIN", "localhost"},
  session_key: {:system, "SESSION_KEY", "_sanbase_sid"}

config :sanbase, SanbaseWeb.Plug.BotLoginPlug,
  bot_login_endpoint: {:system, "BOT_LOGIN_SECRET_ENDPOINT"}

config :sanbase, Sanbase.GrafanaApi,
  grafana_base_url: {:system, "GRAFANA_BASE_URL"},
  grafana_user: {:system, "GRAFANA_USER"},
  grafana_pass: {:system, "GRAFANA_PASS"}

config :sanbase, Sanbase.Intercom, api_key: {:system, "INTERCOM_API_KEY"}

config :sanbase, Sanbase.Promoters.FirstPromoterApi,
  api_id: {:system, "FIRST_PROMOTER_API_ID"},
  api_key: {:system, "FIRST_PROMOTER_API_KEY"}

config :sanbase, Oban.Web,
  repo: Sanbase.Repo,
  queues: [email_queue: 5],
  name: :oban_web

config :kaffy,
  otp_app: :sanbase,
  ecto_repo: Sanbase.Repo,
  router: SanbaseWeb.Router

config :sanbase, Sanbase.Kafka.Consumer,
  enabled?: {:system, "KAFKA_CONSUMER_ENABLED", false},
  metrics_stream_topic: {:system, "KAFKA_METRIC_STREAM_TOPIC", "sanbase_combined_metrics"},
  consumer_group_basename: {:system, "KAFKA_CONSUMER_GROUP_BASENAME", "sanbase_kafka_consumer"}

config :kaffe,
  consumer: [
    message_handler: Sanbase.Kafka.MessageProcessor,
    async_message_ack: false,
    start_with_earliest_message: false,
    offset_reset_policy: :reset_to_latest
  ]

config :nostrum,
  token: {:system, "DISCORD_BOT_QUERY_TOKEN"},
  gateway_intents: [
    :guilds,
    :guild_members,
    :direct_messages,
    :guild_messages,
    :message_content
  ]

# Import configs
import_config "ueberauth_config.exs"
import_config "ex_admin_config.exs"
import_config "scrapers_config.exs"
import_config "notifications_config.exs"
import_config "stripe_config.exs"
import_config "scheduler_config.exs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
