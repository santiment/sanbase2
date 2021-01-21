import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.

config :sanbase,
  influx_store_enabled: false,
  available_slugs_module: Sanbase.DirectAvailableSlugs

config :sanbase, Sanbase, url: {:system, "SANBASE_URL", ""}

config :sanbase, SanbaseWeb.Endpoint,
  http: [port: 4001],
  server: true

# Print only warnings and errors during test. Do not log JSON in tests.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :warn

# Test adapter that allows mocking
config :tesla, adapter: Tesla.Mock

# The logger is causing issues with mocking otherwise. Not really sure why
config :tesla, Tesla.Middleware.Logger, debug: false

config :sanbase, Sanbase.KafkaExporter,
  supervisor: Sanbase.InMemoryKafka.Supervisor,
  producer: Sanbase.InMemoryKafka.Producer

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
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_test",
  pool_size: 5

config :sanbase, Sanbase.Auth.Hmac, secret_key: "Non_empty_key_used_in_tests_only"

config :sanbase, Sanbase.ExternalServices.Coinmarketcap, sync_enabled: false

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 1000

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, sync_enabled: false

config :sanbase, Sanbase.Notifications.PriceVolumeDiff,
  webhook_url: "http://example.com/webhook_url",
  notifications_enabled: true

config :sanbase, Sanbase.Twitter.Store, database: "twitter_followers_data_test"

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  basic_auth_username: "user",
  basic_auth_password: "pass"

config :sanbase, Sanbase.Prices.Store, database: "prices_test"

config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir: "/tmp/sanbase/filestore-test/",
  # Note: without using storage_dir_prefix: "/", a local "tmp/..." dir is used instead of "/tmp/..."
  storage_dir_prefix: "/"

config :sanbase, SanbaseWeb.Plug.VerifyStripeWebhook, webhook_secret: "stripe_webhook_secret"

config :sanbase, Sanbase.Signal, email_channel_enabled: {:system, "EMAIL_CHANNEL_ENABLED", "true"}

# So the router can read it compile time
System.put_env("TELEGRAM_ENDPOINT_RANDOM_STRING", "random_string")

config :sanbase, Sanbase.Telegram,
  bot_username: "SantimentSignalsBotTest",
  telegram_endpoint: "random_string",
  token: "token"

if File.exists?("config/test.secret.exs") do
  import_config "test.secret.exs"
end
