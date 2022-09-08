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

config :sanbase, Oban.Scrapers,
  repo: Sanbase.Repo,
  name: :oban_scrapers,
  queues: [
    cryptocompare_historical_jobs_queue: [limit: 25, paused: true],
    cryptocompare_historical_jobs_pause_resume_queue: 1,
    cryptocompare_historical_add_jobs_queue: 1,
    twitter_followers_migration_queue: [limit: 25, paused: true]
  ],
  plugins: [
    # The default values of interval: 1000, limit: 5000 cause the stager to timeout
    {Oban.Plugins.Stager, interval: 5000, limit: 200},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Sanbase.Cryptocompare.AddHistoricalJobsWorker,
        args: %{type: "schedule_historical_jobs"}, max_attempts: 10}
     ]}
  ]

config :sanbase, Sanbase.Cryptocompare.WebsocketScraper,
  enabled?: {:system, "CRYPTOCOMPARE_WEBSOCKET_PRICES_SCRAPER_ENABLED", "false"}

config :sanbase, Sanbase.Cryptocompare.HistoricalScheduler,
  enabled?: {:system, "CRYPTOCOMPARE_HISTORICAL_OHLCV_PRICES_SCHEDULER_ENABLED", "false"}

config :sanbase, Sanbase.Twitter.FollowersScheduler,
  enabled?: {:system, "TWITTER_FOLLOWERS_SCHEDULER_ENABLED", "false"}
