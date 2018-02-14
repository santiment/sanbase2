# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :sanbase, ecto_repos: [Sanbase.Repo]

config :sanbase, Sanbase.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 5,
  prepare: :unnamed

# Configures the endpoint
config :sanbase, SanbaseWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Vq7Rfo0T4EfiLX2/ryYal3O0l9ebBNhyh58cfWdTAUHxEJGu2p9u1WTQ31Ki4Phj",
  render_errors: [view: SanbaseWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Sanbase.PubSub, adapter: Phoenix.PubSub.PG2],
  website_url: {:system, "WEBSITE_URL", "http://localhost:4000"}

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

config :sanbase, Sanbase.Prices.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "prices"

config :sanbase, Sanbase.Github.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "github_activity"

config :sanbase, SanbaseWorkers.ImportGithubActivity,
  s3_bucket: {:system, "GITHUB_ARCHIVE_BUCKET", "santiment-github-archive"}

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "twitter_followers_data"

config :sanbase, Sanbase.Etherbi.Transactions.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "transactions"

config :sanbase, Sanbase.Etherbi.BurnRate.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "burn_rate"

config :sanbase, Sanbase.Etherbi.TransactionVolume.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "transaction_volume"

config :sanbase, Sanbase.ExternalServices.Etherscan.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "etherscan_transactions"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :ex_admin,
  repo: Sanbase.Repo,
  # MyProject.Web for phoenix >= 1.3.0-rc
  module: SanbaseWeb,
  modules: [
    Sanbase.ExAdmin.Dashboard,
    Sanbase.ExAdmin.Model.Project,
    Sanbase.ExAdmin.Model.ProjectBtcAddress,
    Sanbase.ExAdmin.Model.ProjectEthAddress,
    Sanbase.ExAdmin.Model.Ico,
    Sanbase.ExAdmin.Model.ExchangeEthAddress,
    Sanbase.ExAdmin.Model.Currency,
    Sanbase.ExAdmin.Model.Infrastructure,
    Sanbase.ExAdmin.Model.MarketSegment,
    Sanbase.ExAdmin.Model.ProjectTransparencyStatus,
    Sanbase.ExAdmin.Model.LatestCoinmarketcapData,
    Sanbase.ExAdmin.Model.LatestEthWalletData,
    Sanbase.ExAdmin.Model.LatestBtcWalletData,
    Sanbase.ExAdmin.Notifications.Type,
    Sanbase.ExAdmin.Auth.User,
    Sanbase.ExAdmin.Voting.Poll,
    Sanbase.ExAdmin.Voting.Post
  ],
  basic_auth: [
    username: {:system, "ADMIN_BASIC_AUTH_USERNAME"},
    password: {:system, "ADMIN_BASIC_AUTH_PASSWORD"},
    realm: {:system, "ADMIN_BASIC_AUTH_REALM"}
  ]

config :xain, :after_callback, {Phoenix.HTML, :raw}

config :tesla, adapter: :hackney, recv_timeout: 30_000

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  # 5 minutes
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_PRICES_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_TICKERS_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Etherscan.Worker,
  # 5 minutes
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "ETHERSCAN_CRAWLER_ENABLED", false}

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

config :sanbase, Sanbase.Etherbi.Transactions,
  update_interval: 1000 * 60 * 5,
  sync_enabled: {:system, "ETHERBI_TRANSACTIONS_SYNC_ENABLED", false}

config :sanbase, Sanbase.Etherbi.BurnRate,
  update_interval: 1000 * 60 * 5,
  sync_enabled: {:system, "ETHERBI_BURN_RATE_SYNC_ENABLED", false}

config :sanbase, Sanbase.Etherbi.TransactionVolume,
  update_interval: 1000 * 60 * 5,
  sync_enabled: {:system, "ETHERBI_TRANSACTION_VOLUME_SYNC_ENABLED", false}

config :sanbase, Sanbase.Notifications.CheckPrices,
  webhook_url: {:system, "NOTIFICATIONS_WEBHOOK_URL"},
  notification_channel: {:system, "NOTIFICATIONS_CHANNEL", "#signals-stage"},
  slack_notifications_enabled: {:system, "SLACK_NOTIFICATIONS_ENABLED", false}

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

config :sanbase, Sanbase.Etherbi,
  url: {:system, "ETHERBI_URL"},
  use_cache: {:system, "ETHERBI_USE_CACHE", false}

config :sanbase, Sanbase.MandrillApi,
  apikey: {:system, "MANDRILL_APIKEY"},
  from_email: {:system, "MANDRILL_FROM_EMAIL", "admin@santiment.net"}

config :sanbase, Sanbase.TechIndicators,
  url: {:system, "TECH_INDICATORS_URL"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
