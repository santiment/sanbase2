import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :phoenix_live_view, debug_heex_annotations: true
config :sanbase, Sanbase, url: {:system, "SANBASE_URL", "https://app-stage.santiment.net"}

port = String.to_integer(System.get_env("PORT") || "4000")

config :sanbase, SanbaseWeb.Endpoint,
  http: [
    port: port,
    protocol_options: [
      # Bump up cowboy2's timeout to 100 seconds
      idle_timeout: 100_000
    ]
  ],
  url: [host: "0.0.0.0"],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

config :logger,
  level: :debug,
  truncate: :infinity

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$time][$level][$metadata] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix,
  stacktrace_depth: 20,
  plug_init_mode: :runtime

# Disable the Oban.Web jobs in local env.
# When testing Oban.Web jobs locally comment out these 2 lines
config :sanbase, Oban.Web, queues: false
config :sanbase, Oban.Admin, queues: false

# Disable the Oban.Scrapers jobs in local env.
# When testing Oban.Scrapers jobs locally comment out this line
config :sanbase, Oban.Scrapers, queues: false

config :sanbase, Sanbase.Messaging.Insight, enabled: "false"

config :sanbase, Sanbase.KafkaExporter, producer: Sanbase.InMemoryKafka.Producer

# Configure the postgres database access. These values are default values that
# are used locally when developing. These are not the values that are used in
# production. They are set to some default values that postgres is intialized
# with. When running the app locally these values are overridden by the values
# in the .env.dev or dev.secret.exs files, which are ignored by git and not
# published in the repository. Please do not report these as security issues.
# To create the user for your local env:
# In psql: CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD 'postgres';
# In the terminal: mix ecto.setup
config :sanbase, Sanbase.Repo,
  username: "postgres",
  password: "postgres",
  database: "sanbase_dev",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true

# Clickhousex does not support `:system` tuples. The configuration is done
# by defining defining `:url` in the ClickhouseRepo `init` function.
# These values are default values that are used locally when developing.
# These are not the values that are used in production. They are set to some
# default values that clickhouse is intialized with. When running the app locally
# these values are overridden by the values in the .env.dev or dev.secret.exs files,
# which are ignored by git and not published in the repository.
# Please do not report these as security issues.
config :sanbase, Sanbase.ClickhouseRepo,
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry],
  hostname: "clickhouse",
  port: 8123,
  database: "default",
  username: "default",
  password: "",
  timeout: 60_000,
  pool_size: {:system, "CLICKHOUSE_POOL_SIZE", "3"},
  show_sensitive_data_on_connection_error: true

clickhouse_read_only_opts = [
  adapter: ClickhouseEcto,
  loggers: [Ecto.LogEntry, Sanbase.Prometheus.EctoInstrumenter],
  hostname: "clickhouse",
  port: 8123,
  database: "default",
  username: "sanbase",
  password: "",
  timeout: 600_000,
  pool_size: {:system, "CLICKHOUSE_READONLY_POOL_SIZE", "1"},
  pool_overflow: 3,
  max_overflow: 5,
  show_sensitive_data_on_connection_error: true
]

config :sanbase, Sanbase.ClickhouseRepo.ReadOnly, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.FreeUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.SanbaseMaxUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessProUser, clickhouse_read_only_opts
config :sanbase, Sanbase.ClickhouseRepo.BusinessMaxUser, clickhouse_read_only_opts

config :sanbase, Sanbase.ExternalServices.Etherscan.RateLimiter,
  scale: 1000,
  limit: 5,
  time_between_requests: 250

# These are not the values that are used in production. They are set to some
# default values. When running the app locally these values are overridden by
# the values in the .env.dev or dev.secret.exs files, which are ignored by git
# and not published in the repository. Please do not report these as security
# issues.
config :sanbase, SanbaseWeb.Graphql.AuthPlug,
  basic_auth_username: "user",
  basic_auth_password: "pass"

config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir: "sanbase/filestore/",
  # Note: without using storage_dir_prefix: "/", a local "tmp/..." dir
  # is used instead of "/tmp/..."
  storage_dir_prefix: "/tmp/"

if File.exists?("config/dev.secret.exs") do
  import_config "dev.secret.exs"
end
