use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.

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

# Configure postgres database
config :sanbase, Sanbase.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_test",
  pool_size: 5

# Configure your database
config :sanbase, Sanbase.TimescaleRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_timescale_test",
  pool_size: 5

config :sanbase, Sanbase.Timescaledb, blockchain_schema: nil

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

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  database: "twitter_followers_data_test"

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  basic_auth_username: "user",
  basic_auth_password: "pass"

config :sanbase, Sanbase.Prices.Store, database: "prices_test"

config :arc,
  storage: Arc.Storage.Local,
  storage_dir: "/tmp/sanbase/filestore-test/"

config :sanbase, Sanbase.Elasticsearch.Cluster, api: Sanbase.ElasticsearchMock

config :sanbase, Sanbase.Elasticsearch, indices: "index1,index2,index3,index4"

# So the router can read it compile time
System.put_env("TELEGRAM_ENDPOINT_RANDOM_STRING", "random_string")

config :sanbase, Sanbase.Telegram,
  bot_username: "SantimentSignalsBotTest",
  telegram_endpoint: "random_string",
  token: "token"

if File.exists?("config/test.secret.exs") do
  import_config "test.secret.exs"
end
