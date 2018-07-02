# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :sanbase, ecto_repos: [Sanbase.Repo, Sanbase.TimescaleRepo]

config :ecto, json_library: Jason

config :sanbase, Sanbase, environment: "#{Mix.env()}"

config :sanbase, Sanbase.ClickhouseRepo, adapter: Ecto.Adapters.Postgres

config :sanbase, Sanbase.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: {:system, "SANBASE_POOL_SIZE", "20"},
  # because of pgbouncer
  prepare: :unnamed

config :sanbase, Sanbase.TimescaleRepo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: {:system, "TIMESCALE_POOL_SIZE", "30"},
  # because of pgbouncer
  prepare: :unnamed

config :sanbase, Sanbase.Timescaledb,
  blockchain_schema: {:system, "TIMESCALEDB_BLOCKCHAIN_SCHEMA", "etherbi"}

config :sanbase, Sanbase.Auth.Hmac, secret_key: {:system, "APIKEY_HMAC_SECRET_KEY", nil}

config :sanbase, Sanbase.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10,
  prepare: :unnamed

config :sanbase, Sanbase.Auth.Hmac, secret_key: {:system, "APIKEY_HMAC_SECRET_KEY", nil}

# Configures the endpoint
config :sanbase, SanbaseWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Vq7Rfo0T4EfiLX2/ryYal3O0l9ebBNhyh58cfWdTAUHxEJGu2p9u1WTQ31Ki4Phj",
  render_errors: [view: SanbaseWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Sanbase.PubSub, adapter: Phoenix.PubSub.PG2],
  # should be removed after app.santiment.net migration
  website_url: {:system, "WEBSITE_URL", "http://localhost:4000"},
  backend_url: {:system, "BACKEND_URL", "http://localhost:4000"},
  frontend_url: {:system, "FRONTEND_URL", "http://localhost:4000"}

# Do not log SASL crash reports
config :sasl, sasl_error_logger: false

# Do not log SASL crash reports
config :sasl, sasl_error_logger: false

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  handle_otp_reports: true,
  handle_sasl_reports: true

# Error tracking
config :sentry,
  included_environments: [:prod],
  environment_name: Mix.env()

config :sanbase, SanbaseWorkers.ImportGithubActivity,
  s3_bucket: {:system, "GITHUB_ARCHIVE_BUCKET", "santiment-github-archive"}

config :sanbase, SanbaseWorkers.ImportGithubActivity,
  s3_bucket: {:system, "GITHUB_ARCHIVE_BUCKET", "santiment-github-archive"}

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "twitter_followers_data"

config :sanbase, Sanbase.Etherbi.Transactions.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_exchange_funds_flow"

config :sanbase, Sanbase.Etherbi.BurnRate.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_burn_rate"

config :sanbase, Sanbase.Etherbi.TransactionVolume.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_transaction_volume"

config :sanbase, Sanbase.Etherbi.DailyActiveAddresses.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_daily_active_addresses"

config :sanbase, Sanbase.ExternalServices.Etherscan.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "etherscan_transactions"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :xain, :after_callback, {Phoenix.HTML, :raw}

config :tesla, adapter: Tesla.Adapter.Hackney, recv_timeout: 30_000

config :sanbase, SanbaseWeb.Guardian,
  issuer: "santiment",
  secret_key: {SanbaseWeb.Guardian, :get_config, [:secret_key_base]}

config :sanbase, Sanbase.InternalServices.Ethauth,
  url: {:system, "ETHAUTH_URL"},
  basic_auth_username: {:system, "ETHAUTH_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "ETHAUTH_BASIC_AUTH_PASSWORD"}

config :sanbase, Sanbase.InternalServices.Parity,
  url: {:system, "PARITY_URL"},
  basic_auth_username: {:system, "PARITY_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "PARITY_BASIC_AUTH_PASSWORD"}

config :faktory_worker_ex,
  host: {:system, "FAKTORY_HOST", "localhost"},
  port: {:system, "FAKTORY_PORT", 7419},
  client: [
    pool: 1
  ],
  worker: [
    concurrency: 1,
    queues: ["default", "data_migrations"]
  ],
  start_workers: {:system, "FAKTORY_WORKERS_ENABLED", false}

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  basic_auth_username: {:system, "GRAPHQL_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "GRAPHQL_BASIC_AUTH_PASSWORD"}

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "eu-central-1"

config :sanbase, Sanbase.MandrillApi,
  apikey: {:system, "MANDRILL_APIKEY"},
  from_email: {:system, "MANDRILL_FROM_EMAIL", "admin@santiment.net"}

config :sanbase, Sanbase.TechIndicators, url: {:system, "TECH_INDICATORS_URL"}

config :arc,
  storage: Arc.Storage.S3,
  # To support AWS regions other than US Standard
  virtual_host: true,
  bucket: {:system, "POSTS_IMAGE_BUCKET"}

config :sanbase, Sanbase.Oauth2.Hydra,
  base_url: {:system, "HYDRA_BASE_URL", "http://localhost:4444"},
  token_uri: {:system, "HYDRA_TOKEN_URI", "/oauth2/token"},
  consent_uri: {:system, "HYDRA_CONSENT_URI", "/oauth2/consent/requests"},
  client_id: {:system, "HYDRA_CLIENT_ID", "consent-app"},
  client_secret: {:system, "HYDRA_CLIENT_SECRET", "consent-secret"},
  clients_that_require_san_tokens:
    {:system, "CLIENTS_THAT_REQUIRE_SAN_TOKENS", "{\"grafana\": 100}"}

config :sanbase, SanbaseWeb.Graphql.PlugAttack,
  rate_limit_period: {:system, "RATE_LIMIT_PERIOD", "10000"},
  rate_limit_max_requests: {:system, "RATE_LIMIT_MAX_REQUESTS", "40"}

config :sanbase, SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction,
  restrict_to_in_days: {:system, "RESTRICT_TO_IN_DAYS", "1"},
  restrict_from_in_days: {:system, "RESTRICT_FROM_IN_MONTHS", "90"},
  required_san_stake_full_access: {:system, "REQUIRED_SAN_STAKE_FULL_ACCESS", "1000"}

config :sanbase, Sanbase.Discourse,
  url: {:system, "DISCOURSE_URL", "https://discourse.stage.internal.santiment.net/"},
  api_key: {:system, "DISCOURSE_API_KEY"},
  insights_category: {:system, "DISCOURSE_INSIGHTS_CATEGORY", "sanbaseinsights"}

# Import configs
import_config "ex_admin_config.exs"
import_config "influxdb_config.exs"
import_config "scrapers_config.exs"
import_config "notifications_config.exs"
import_config "elasticsearch_config.exs"

config :sanbase, Sanbase.Prices.Store,
  host: "localhost"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4,
                                 cleanup_interval_ms: 60_000 * 10]}

config :sanbase, Sanbase.ExternalServices.Github,
  # 60 minutes
  update_interval: 60 * 1000 * 60,
  sync_enabled: {:system, "GITHUB_SCHEDULER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Etherscan.Requests,
  apikey: {:system, "ETHERSCAN_APIKEY"}

config :sanbase, Sanbase.ExternalServices.TwitterData.Worker,
  consumer_key: {:system, "TWITTER_CONSUMER_KEY"},
  consumer_secret: {:system, "TWITTER_CONSUMER_SECRET"},
  # 6 hours
  update_interval: 1000 * 60 * 60 * 6,
  sync_enabled: {:system, "TWITTER_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.TwitterData.HistoricalData,
  apikey: {:system, "TWITTERCOUNTER_API_KEY"},
  # 1 day
  update_interval: 1000 * 60 * 60 * 24,
  sync_enabled: {:system, "TWITTERCOUNTER_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.Notifications.CheckPrices,
  webhook_url: {:system, "CHECK_PRICES_WEBHOOK_URL"},
  notification_channel: {:system, "CHECK_PRICES_CHANNEL", "#signals-stage"},
  slack_notifications_enabled: {:system, "CHECK_PRICES_NOTIFICATIONS_ENABLED", false}

config :sanbase, Sanbase.Notifications.PriceVolumeDiff,
  webhook_url: {:system, "PRICE_VOLUME_DIFF_WEBHOOK_URL"},
  window_type: {:system, "PRICE_VOLUME_DIFF_WINDOW_TYPE"},
  approximation_window: {:system, "PRICE_VOLUME_DIFF_APPROXIMATION_WINDOW", "14"},
  comparison_window: {:system, "PRICE_VOLUME_DIFF_COMPARISON_WINDOW", "7"},
  notification_threshold: {:system, "PRICE_VOLUME_DIFF_NOTIFICATION_THRESHOLD", "0.01"},
  notification_volume_threshold:
    {:system, "PRICE_VOLUME_DIFF_NOTIFICATION_VOLUME_THRESHOLD", "100000"},
  notifications_cooldown: {:system, "PRICE_VOLUME_DIFF_NOTIFICATIONS_COOLDOWN", "86400"},
  debug_url: {:system, "PRICE_VOLUME_DIFF_DEBUG_URL"},
  notifications_enabled: {:system, "PRICE_VOLUME_DIFF_NOTIFICATIONS_ENABLED", false}

config :sanbase, SanbaseWeb.Guardian,
  issuer: "santiment",
  secret_key: {SanbaseWeb.Guardian, :get_config, [:secret_key_base]}

config :sanbase, Sanbase.InternalServices.Ethauth,
  url: {:system, "ETHAUTH_URL"},
  basic_auth_username: {:system, "ETHAUTH_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "ETHAUTH_BASIC_AUTH_PASSWORD"}

config :sanbase, Sanbase.InternalServices.Parity,
  url: {:system, "PARITY_URL"},
  basic_auth_username: {:system, "PARITY_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "PARITY_BASIC_AUTH_PASSWORD"}

config :faktory_worker_ex,
  host: {:system, "FAKTORY_HOST", "localhost"},
  port: {:system, "FAKTORY_PORT", 7419},
  client: [
    pool: 1
  ],
  worker: [
    concurrency: 1,
    queues: ["default", "data_migrations"]
  ],
  start_workers: {:system, "FAKTORY_WORKERS_ENABLED", false}

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  basic_auth_username: {:system, "GRAPHQL_BASIC_AUTH_USERNAME"},
  basic_auth_password: {:system, "GRAPHQL_BASIC_AUTH_PASSWORD"}

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "eu-central-1"

config :sanbase, Sanbase.MandrillApi,
  apikey: {:system, "MANDRILL_APIKEY"},
  from_email: {:system, "MANDRILL_FROM_EMAIL", "admin@santiment.net"}

config :sanbase, Sanbase.TechIndicators, url: {:system, "TECH_INDICATORS_URL"}

config :arc,
  storage: Arc.Storage.S3,
  # To support AWS regions other than US Standard
  virtual_host: true,
  bucket: {:system, "POSTS_IMAGE_BUCKET"}

config :sanbase, Sanbase.Oauth2.Hydra,
  base_url: {:system, "HYDRA_BASE_URL", "http://localhost:4444"},
  token_uri: {:system, "HYDRA_TOKEN_URI", "/oauth2/token"},
  consent_uri: {:system, "HYDRA_CONSENT_URI", "/oauth2/consent/requests"},
  client_id: {:system, "HYDRA_CLIENT_ID", "consent-app"},
  client_secret: {:system, "HYDRA_CLIENT_SECRET", "consent-secret"},
  clients_that_require_san_tokens:
    {:system, "CLIENTS_THAT_REQUIRE_SAN_TOKENS", "{\"grafana\": 100}"}

config :sanbase, SanbaseWeb.Graphql.PlugAttack,
  rate_limit_period: {:system, "RATE_LIMIT_PERIOD", "10000"},
  rate_limit_max_requests: {:system, "RATE_LIMIT_MAX_REQUESTS", "40"}

config :sanbase, SanbaseWeb.Graphql.Middlewares.ApiDelay,
  required_san_stake_realtime_api: {:system, "REQUIRED_SAN_STAKE_REALTIME_API", "1000"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
