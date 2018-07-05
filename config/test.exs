use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sanbase, SanbaseWeb.Endpoint,
  http: [port: 4001],
  server: true

# Print only warnings and errors during test
config :logger, level: :warn

# Test adapter that allows mocking
config :tesla, adapter: :mock

# Configure your database
config :sanbase, Sanbase.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "sanbase_test",
  # closest to real case as there are 3 pods with 10 connections each
  pool_size: 30

config :sanbase, Sanbase.Auth.Hmac, secret_key: "Non_empty_key_used_in_tests_only"

config :sanbase, Sanbase.ExternalServices.Coinmarketcap, sync_enabled: false

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 1000

config :sanbase, Sanbase.ExternalServices.Etherscan.Requests, apikey: "myapikey"

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, sync_enabled: false

config :sanbase, Sanbase.ExternalServices.Etherscan.Worker, sync_enabled: false

config :faktory_worker_ex,
  client: [
    pool: 0
  ],
  start_workers: false

config :sanbase, Sanbase.Notifications.CheckPrices,
  webhook_url: "http://example.com/webhook_url",
  slack_notifications_enabled: true

config :sanbase, Sanbase.Notifications.PriceVolumeDiff,
  webhook_url: "http://example.com/webhook_url",
  notifications_enabled: true

config :sanbase, Sanbase.Github.Store, database: "github_activity_test"

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  database: "twitter_followers_data_test"

config :sanbase, Sanbase.Etherbi.Transactions.Store, database: "erc20_exchange_funds_flow_test"

config :sanbase, Sanbase.Etherbi.BurnRate.Store, database: "erc20_burn_rate_flow_test"

config :sanbase, Sanbase.Etherbi.TransactionVolume.Store,
  database: "erc20_transaction_volume_test"

config :sanbase, Sanbase.Etherbi.DailyActiveAddresses.Store,
  database: "erc20_daily_active_addresses_test"

config :sanbase, SanbaseWeb.Graphql.ContextPlug,
  basic_auth_username: "user",
  basic_auth_password: "pass"

config :sanbase, Sanbase.Prices.Store, database: "prices_test"

config :sanbase, Sanbase.ExternalServices.Etherscan.Store, database: "etherscan_transactions_test"

config :arc,
  storage: Arc.Storage.Local,
  storage_dir: "/tmp/sanbase/filestore-test/"

if File.exists?("config/test.secret.exs") do
  import_config "test.secret.exs"
end
