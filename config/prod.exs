import Config

config :sanbase, SanbaseWeb.Endpoint,
  http: [
    port: {:system, "PORT"},
    protocol_options: [
      max_header_name_length: 64,
      max_header_value_length: 8192,
      max_request_line_length: 16_384,
      max_headers: 100,
      # Bump up cowboy2's timeout to 100 seconds
      idle_timeout: 100_000
    ]
  ],
  url: [host: "localhost", port: {:system, "PORT"}],
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  version: Application.spec(:sanbase, :vsn),
  load_from_system_env: true,
  check_origin: [
    "//*.santiment.net",
    "//*.sanr.app",
    "//*.sanbase-admin.stage.san",
    "//*.sanbase-admin.production.san"
  ]

# Clickhousex does not support `:system` tuples. The configuration is done
# by defining defining `:url` in the ClickhouseRepo `init` function.
config :sanbase, Sanbase.ClickhouseRepo,
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry],
  hostname: "clickhouse",
  port: 8123,
  database: "not_secret_default",
  username: "not_secret_default",
  password: "",
  timeout: 100_000,
  pool_size: {:system, "CLICKHOUSE_POOL_SIZE", "25"},
  pool_overflow: 5

clickhouse_read_only_opts = [
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry, Sanbase.Prometheus.EctoInstrumenter],
  hostname: "clickhouse",
  port: 8123,
  database: "not_secret_default",
  username: "not_secret_default",
  password: "",
  timeout: 100_000,
  pool_size: {:system, "CLICKHOUSE_READONLY_POOL_SIZE", "0"},
  pool_overflow: 3,
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

config :sanbase, Sanbase.Kafka.Consumer, enabled?: {:system, "KAFKA_CONSUMER_ENABLED", true}

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
