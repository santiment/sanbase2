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
  pool_size: 30

# Configure your database
config :sanbase, Sanbase.TimescaleRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_timescale_test",
  pool_size: 30

config :sanbase, Sanbase.Timescaledb, blockchain_schema: nil

config :sanbase, Sanbase.Auth.Hmac, secret_key: "Non_empty_key_used_in_tests_only"

config :sanbase, Sanbase.ExternalServices.Coinmarketcap, sync_enabled: false

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 1000

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, sync_enabled: false

config :faktory_worker_ex,
  client: [
    pool: 0
  ],
  start_workers: false

config :sanbase, Sanbase.Notifications.PriceVolumeDiff,
  webhook_url: "http://example.com/webhook_url",
  notifications_enabled: true

config :sanbase, Sanbase.Github.Store, database: "github_activity_test"

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

if File.exists?("config/test.secret.exs") do
  import_config "test.secret.exs"
end
