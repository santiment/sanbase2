# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :sanbase, Sanbase.Prices.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 15, size: 30],
  database: "prices"

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "twitter_followers_data"
