import Config

config :sanbase, SanbaseWeb.Endpoint,
  http: [
    port: {:system, "PORT"},
    protocol_options: [
      max_header_name_length: 64,
      max_header_value_length: 8192,
      max_request_line_length: 16_384,
      max_headers: 100
    ]
  ],
  url: [host: "localhost", port: {:system, "PORT"}],
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: '.',
  version: Application.spec(:sanbase, :vsn),
  load_from_system_env: true,
  secret_key_base: "${SECRET_KEY_BASE}",
  live_view: [signing_salt: "${PHOENIX_LIVE_VIEW_SIGNING_SALT}"],
  check_origin: ["//*.santiment.net"]

# Clickhousex does not support `:system` tuples. The configuration is done
# by defining defining `:url` in the ClickhouseRepo `init` function.
config :sanbase, Sanbase.ClickhouseRepo,
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry, Sanbase.Prometheus.EctoInstrumenter],
  hostname: "clickhouse",
  port: 8123,
  database: "not_secret_default",
  username: "not_secret_default",
  password: "",
  timeout: 60_000,
  pool_size: {:system, "CLICKHOUSE_POOL_SIZE", "30"},
  pool_overflow: 5

# Do not print debug messages in production
config :logger, level: :info

config :sanbase, Sanbase.Kafka.Consumer, enabled?: {:system, "KAFKA_CONSUMER_ENABLED", true}

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 250

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  api_url: "https://pro-api.coinmarketcap.com/"

config :sanbase, SanbaseWeb.Plug.SessionPlug,
  domain: {:system, "SANTIMENT_ROOT_DOMAIN", ".santiment.net"}

config :ethereumex,
  url: "${PARITY_URL}",
  http_options: [timeout: 25_000, recv_timeout: 25_000]

if File.exists?("config/prod.secret.exs") do
  import_config "prod.secret.exs"
end
