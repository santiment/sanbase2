# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :sanbase, ecto_repos: [Sanbase.Repo]

config :sanbase, Sanbase, environment: "#{Mix.env()}"

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
  website_url: {:system, "WEBSITE_URL", "http://localhost:4000"},
  api_url: {:system, "API_URL", "https://api.santiment.net/graphql"}

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

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :xain, :after_callback, {Phoenix.HTML, :raw}

config :tesla, adapter: :hackney, recv_timeout: 30_000

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
  date_to_in_days: {:system, "DATE_TO_IN_DAYS", "1"},
  date_from_in_months: {:system, "DATE_FROM_IN_MONTHS", "3"},
  required_san_stake_full_access: {:system, "REQUIRED_SAN_STAKE_FULL_ACCESS", "1000"}

# Import configs
import_config "ex_admin_config.exs"
import_config "influxdb_config.exs"
import_config "scrapers_config.exs"
import_config "notifications_config.exs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
