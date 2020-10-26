# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :sanbase, Sanbase.Influxdb.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086}

config :sanbase, Sanbase.Twitter.Store,
  init: {Sanbase.Twitter.Store, :init},
  host: "localhost",
  port: 8086,
  pool: [max_overflow: 20, size: 20],
  database: "twitter_followers_data"
