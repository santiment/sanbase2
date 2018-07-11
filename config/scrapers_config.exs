# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  # 5 minutes
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_PRICES_ENABLED", false}

# TODO: Change after switching over to only this cmc
config :sanbase, Sanbase.ExternalServices.Coinmarketcap2,
  # 5 minutes
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_TICKERS_ENABLED", false},
  top_projects_to_follow: {:system, "TOP_PROJECTS_TO_FOLLOW", "25"}

# TODO: Change after switching over to only this cmc
config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2,
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "COINMARKETCAP_TICKER_FETCHER_ENABLED", false},
  top_projects_to_follow: {:system, "TOP_PROJECTS_TO_FOLLOW", "25"}

config :sanbase, Sanbase.ExternalServices.Etherscan.Worker,
  # 5 minutes
  update_interval: 5 * 1000 * 60,
  sync_enabled: {:system, "ETHERSCAN_CRAWLER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Github,
  # 60 minutes
  update_interval: 60 * 1000 * 60,
  sync_enabled: {:system, "GITHUB_SCHEDULER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Etherscan.Requests,
  apikey: {:system, "ETHERSCAN_APIKEY"}

config :sanbase, Sanbase.ExternalServices.TwitterData.Worker,
  consumer_key: {:system, "TWITTER_CONSUMER_KEY"},
  consumer_secret: {:system, "TWITTER_CONSUMER_SECRET"},
  # 6 hours
  update_interval: 1000 * 60 * 60 * 6,
  sync_enabled: {:system, "TWITTER_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.TwitterData.HistoricalData,
  apikey: {:system, "TWITTERCOUNTER_API_KEY"},
  # 1 day
  update_interval: 1000 * 60 * 60 * 24,
  sync_enabled: {:system, "TWITTERCOUNTER_SCRAPER_ENABLED", false}
