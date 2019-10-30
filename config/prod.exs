import Config

config :sanbase, SanbaseWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: "localhost", port: {:system, "PORT"}],
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: '.',
  version: Application.spec(:sanbase, :vsn),
  load_from_system_env: true,
  secret_key_base: "${SECRET_KEY_BASE}",
  check_origin: [
    "https://api-stage.santiment.net",
    "https://api.santiment.net",
    "https://app-stage.santiment.net",
    "https://app.santiment.net"
  ]

config :sanbase, ecto_repos: [Sanbase.Repo]

# Clickhousex does not support `:system` tuples. The configuration is done
# by defining defining `:url` in the ClickhouseRepo `init` function.
config :sanbase, Sanbase.ClickhouseRepo,
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry, Sanbase.Prometheus.EctoInstrumenter],
  hostname: "clickhouse",
  port: 8123,
  database: "default",
  username: "default",
  password: "",
  pool_timeout: 60_000,
  timeout: 60_000,
  pool_size: {:system, "CLICKHOUSE_POOL_SIZE", "30"},
  max_overflow: 5

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
