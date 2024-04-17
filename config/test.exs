import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.

config :phoenix, :stacktrace_depth, 60

config :sanbase,
  available_slugs_module: Sanbase.DirectAvailableSlugs

config :sanbase, Sanbase, url: {:system, "SANBASE_URL", ""}

config :sanbase, SanbaseWeb.Endpoint,
  http: [port: 4001],
  server: true

config :ex_aws,
  access_key_id: "test_id",
  secret_access_key: "test_secret",
  region: "eu-central-1"

config :sanbase, Sanbase.PresignedS3Url.S3,
  access_key_id: "test_id",
  secret_access_key: "test_secret"

# Print only warnings and errors during test. Do not log JSON in tests.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :warning

config :sanbase, Sanbase.RepoReader, projects_data_endpoint_secret: "no_secret"

config :sanbase, Sanbase.ApiCallLimit,
  quota_size: 10,
  quota_size_max_offset: 10

config :sanbase, Sanbase.Accounts.Interaction,
  interaction_cooldown_seconds: 0,
  datetime_module: Sanbase.Interaction.DateTime

# Test adapter that allows mocking
config :tesla, adapter: Tesla.Mock

# The logger is causing issues with mocking otherwise. Not really sure why
config :tesla, Tesla.Middleware.Logger, debug: false

config :sanbase, Sanbase.KafkaExporter,
  supervisor: Sanbase.InMemoryKafka.Supervisor,
  producer: Sanbase.InMemoryKafka.Producer

config :sanbase, Sanbase.EventBus.KafkaExporterSubscriber,
  buffering_max_messages: 0,
  can_send_after_interval: 0,
  kafka_flush_timeout: 0

config :sanbase, Sanbase.ExternalServices.RateLimiting.Server,
  implementation_module: Sanbase.ExternalServices.RateLimiting.TestServer

# Configure postgres database
config :sanbase, Sanbase.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  username: "postgres",
  password: "postgres",
  database: "sanbase_test",
  pool_size: 5

config :sanbase, Sanbase.ClickhouseRepo,
  clickhouse_repo_enabled?: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_test",
  pool_size: 1

clickhouse_read_only_opts = [
  clickhouse_repo_enabled?: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_test",
  pool_size: 1
]

config :sanbase, Sanbase.ClickhouseRepo.ReadOnly, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.FreeUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseMaxUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessProUser, clickhouse_read_only_opts

config :sanbase, Sanbase.Accounts.Hmac, secret_key: "Non_empty_key_used_in_tests_only"

config :sanbase, Sanbase.ExternalServices.Coinmarketcap, sync_enabled: false

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 1000

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, sync_enabled: false

config :sanbase, SanbaseWeb.Graphql.AuthPlug,
  basic_auth_username: "user",
  basic_auth_password: "pass"

config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir: "/tmp/sanbase/filestore-test/",
  # Note: without using storage_dir_prefix: "/", a local "tmp/..." dir is used instead of "/tmp/..."
  storage_dir_prefix: "/"

config :sanbase, SanbaseWeb.Plug.VerifyStripeWebhook, webhook_secret: "stripe_webhook_secret"

config :sanbase, Sanbase.Alert, email_channel_enabled: {:system, "EMAIL_CHANNEL_ENABLED", "true"}

config :sanbase, Oban.Scrapers,
  name: :oban_scrapers,
  testing: :manual

config :sanbase, Oban.Web,
  name: :oban_web,
  testing: :manual

config :sanbase, Sanbase.Cryptocompare.Price.HistoricalScheduler,
  enabled?: {:system, "CRYPTOCOMPARE_HISTORICAL_OHLCV_PRICES_SCHEDULER_ENABLED", "true"}

# So the router can read it compile time
System.put_env("TELEGRAM_ENDPOINT_RANDOM_STRING", "random_string")

config :sanbase, Sanbase.Telegram,
  bot_username: "SantimentAlertsBotTest",
  telegram_endpoint: "random_string",
  token: "token"

# Increase the limits in test env so they are not hit unless
# the limit is intentionally lowered by using Application.put_env
config :sanbase, Sanbase.Comment,
  creation_limit_hour: 1000,
  creation_limit_day: 1000,
  creation_limit_minute: 1000

# Increase the limits in test env so they are not hit unless
# the limit is intentionally lowered by using Application.put_env
config :sanbase, Sanbase.Insight.Post,
  creation_limit_hour: 1000,
  creation_limit_day: 1000,
  creation_limit_minute: 1000

if(File.exists?("config/test.secret.exs")) do
  import_config "test.secret.exs"
end
