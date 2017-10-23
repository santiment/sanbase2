use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sanbase, SanbaseWeb.Endpoint,
  http: [port: 4001],
  server: true

config :sanbase, node_server: "http://localhost:3001"

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :sanbase, Sanbase.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :hound, driver: "chrome_driver"

if File.exists?("config/test.secret.exs") do
  import_config "test.secret.exs"
end
