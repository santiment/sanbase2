import Config

config :sanbase, Sanbase.ExternalServices.Coinmarketcap,
  update_interval: 5 * 1000 * 60,
  api_url: {:system, "COINMARKETCAP_API_URL", "https://sandbox-api.coinmarketcap.com/"},
  api_key: {:system, "COINMARKETCAP_API_KEY", ""},
  sync_enabled: {:system, "COINMARKETCAP_SCRAPER_ENABLED", false}

config :sanbase, Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,
  update_interval: {:system, "COINMARKETCAP_API_CALL_INTERVAL", "300"},
  projects_number: {:system, "COINMARKETCAP_API_PROJECTS_NUMBER", "2500"},
  sync_enabled: {:system, "COINMARKETCAP_TICKER_FETCHER_ENABLED", false},
  top_projects_to_follow: {:system, "TOP_PROJECTS_TO_FOLLOW", "25"}

config :sanbase, Sanbase.ExternalServices.Etherscan.Requests,
  apikey: {:system, "ETHERSCAN_APIKEY", ""}

config :sanbase, Oban.Scrapers,
  repo: Sanbase.Repo,
  name: :oban_scrapers,
  stage_interval: 5_000,
  queues: [
    # Cryptocompare OHLCV price/volume queues
    cryptocompare_historical_jobs_queue: [limit: 25, paused: true],
    cryptocompare_historical_jobs_pause_resume_queue: 1,
    cryptocompare_historical_add_jobs_queue: 1,
    # Cryptocompare open interest queues
    cryptocompare_open_interest_historical_jobs_queue: [limit: 10, paused: true],
    cryptocompare_open_interest_historical_jobs_pause_resume_queue: 1,
    # Cryptocompare funding rate queues
    cryptocompare_funding_rate_historical_jobs_queue: [limit: 10, paused: true],
    cryptocompare_funding_rate_historical_jobs_pause_resume_queue: 1,
    # Watchdog that resumes cryptocompare queues stuck in paused state
    cryptocompare_watchdog_queue: 1,
    # Twitter queues
    twitter_followers_migration_queue: [limit: 25, paused: true]
  ],
  plugins: [
    # Prune completed/discarded jobs after 7 days. The unique period on
    # historical workers is set to match. Keeping completed jobs for longer
    # causes the oban_jobs table (and its GIN indexes) to bloat, leading to
    # progressively higher Postgres CPU usage.
    {Oban.Plugins.Pruner, max_age: 7 * 86_400},
    # Rescue jobs orphaned in the `executing` state by dead pods (e.g. a deploy
    # kills a pod mid-job): back to available, or discarded when attempts are
    # exhausted. Lifeline is purely time-based, so rescue_after must exceed the
    # longest legitimate execution on this instance — AddHistoricalJobsWorker
    # has a 60m timeout, hence 90m. Runs on the leader, checks once a minute.
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(90)},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Sanbase.Cryptocompare.AddHistoricalJobsWorker,
        args: %{"type" => "schedule_historical_price_jobs"}, max_attempts: 10},
       {"0 * * * *", Sanbase.Cryptocompare.AddHistoricalJobsWorker,
        args: %{"type" => "schedule_historical_open_interest_jobs"}, max_attempts: 10},
       {"0 * * * *", Sanbase.Cryptocompare.AddHistoricalJobsWorker,
        args: %{"type" => "schedule_historical_funding_rate_jobs"}, max_attempts: 10},
       {"*/10 * * * *", Sanbase.Cryptocompare.QueueWatchdogWorker}
     ]}
  ]

config :sanbase, Sanbase.Cryptocompare.Price.WebsocketScraper,
  enabled?: {:system, "CRYPTOCOMPARE_WEBSOCKET_PRICES_SCRAPER_ENABLED", "false"}

config :sanbase, Sanbase.Cryptocompare.Price.HistoricalScheduler,
  enabled?: {:system, "CRYPTOCOMPARE_HISTORICAL_OHLCV_PRICES_SCHEDULER_ENABLED", "false"}

config :sanbase, Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler,
  enabled?: {:system, "CRYPTOCOMPARE_HISTORICAL_OPEN_INTEREST_SCHEDULER_ENABLED", "false"}

config :sanbase, Sanbase.Cryptocompare.FundingRate.HistoricalScheduler,
  enabled?: {:system, "CRYPTOCOMPARE_HISTORICAL_FUNDING_RATE_SCHEDULER_ENABLED", "false"}

config :sanbase, Sanbase.Hyperliquid.Bbo.WebsocketScraper,
  enabled?: {:system, "HYPERLIQUID_WS_ENABLED", "false"},
  coalesce_window_ms: {:system, "HYPERLIQUID_BBO_COALESCE_MS", "1000"}

config :sanbase, Sanbase.Hyperliquid.Bbo.CoinUniverse,
  verify_on_write?: {:system, "HYPERLIQUID_VERIFY_COINS_ON_WRITE", "true"}

# ignored_coins: comma-separated coin names the BBO scraper must never
# subscribe to — operator escape hatch for coins whose subscribe kills the
# connection. enabled?: toggles the probation/probe/conviction workflow
# (the ignore list and the universe audit stay active regardless).
config :sanbase, Sanbase.Hyperliquid.Bbo.Quarantine,
  ignored_coins: {:system, "HYPERLIQUID_IGNORED_COINS", ""},
  enabled?: {:system, "HYPERLIQUID_QUARANTINE_ENABLED", "true"}
