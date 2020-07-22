# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  update_interval: 5 * 1000 * 60,
  api_url: "https://sandbox-api.coinmarketcap.com/",
  api_key: {:system, "COINMARKETCAP_API_KEY", ""},
  sync_enabled: {:system, "COINMARKETCAP_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,
  update_interval: {:system, "COINMARKETCAP_API_CALL_INTERVAL", "300"},
  projects_number: {:system, "COINMARKETCAP_API_PROJECTS_NUMBER", "2500"},
  sync_enabled: {:system, "COINMARKETCAP_TICKER_FETCHER_ENABLED", false},
  top_projects_to_follow: {:system, "TOP_PROJECTS_TO_FOLLOW", "25"}

config :sanbase, Sanbase.ExternalServices.Etherscan.Requests,
  apikey: {:system, "ETHERSCAN_APIKEY", ""}

config :sanbase, Sanbase.Twitter.Worker,
  consumer_key: {:system, "TWITTER_CONSUMER_KEY"},
  consumer_secret: {:system, "TWITTER_CONSUMER_SECRET"},
  # 6 hours
  update_interval: 1000 * 60 * 60 * 6,
  sync_enabled: {:system, "TWITTER_SCRAPER_ENABLED", false}
