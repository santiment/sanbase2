import Config

# The ClickHouse configuration is done by defining `:url` in the
# ClickhouseRepo `init` function.
config :sanbase, Sanbase.ClickhouseRepo,
  adapter: Ecto.Adapters.ClickHouse,
  loggers: [Ecto.LogEntry],
  hostname: "clickhouse",
  port: 8123,
  database: "not_secret_default",
  username: "not_secret_default",
  password: "",
  pool_size: {:system, "CLICKHOUSE_POOL_SIZE", "25"},
  max_overflow: 5

clickhouse_read_only_opts = [
  adapter: Ecto.Adapters.ClickHouse,
  loggers: [Ecto.LogEntry, Sanbase.Prometheus.EctoInstrumenter],
  hostname: "clickhouse",
  port: 8123,
  database: "not_secret_default",
  username: "not_secret_default",
  password: "",
  pool_size: {:system, "CLICKHOUSE_READONLY_POOL_SIZE", "0"},
  max_overflow: 5
]

config :sanbase, Sanbase.ClickhouseRepo.ReadOnly, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.FreeUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseMaxUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessMaxUser, clickhouse_read_only_opts

# Do not print debug messages in production
config :logger, level: :info

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 250

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  api_url: "https://pro-api.coinmarketcap.com/"

config :sanbase, SanbaseWeb.Plug.SessionPlug,
  domain: {:system, "SANTIMENT_ROOT_DOMAIN", ".santiment.net"}

if File.exists?("config/prod.secret.exs") do
  import_config "prod.secret.exs"
end
