# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :sanbase, Sanbase.Prices.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "prices"

config :sanbase, Sanbase.Github.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "github_activity"

config :sanbase, Sanbase.ExternalServices.TwitterData.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "twitter_followers_data"

config :sanbase, Sanbase.Etherbi.Transactions.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_exchange_funds_flow"

config :sanbase, Sanbase.Etherbi.BurnRate.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_burn_rate"

config :sanbase, Sanbase.Etherbi.TransactionVolume.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_transaction_volume"

config :sanbase, Sanbase.Etherbi.DailyActiveAddresses.Store,
  host: {:system, "ETHERBI_INFLUXDB_HOST", "localhost"},
  port: {:system, "ETHERBI_INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "erc20_daily_active_addresses"

config :sanbase, Sanbase.ExternalServices.Etherscan.Store,
  host: {:system, "INFLUXDB_HOST", "localhost"},
  port: {:system, "INFLUXDB_PORT", 8086},
  pool: [max_overflow: 10, size: 20],
  database: "etherscan_transactions"
