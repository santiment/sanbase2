import Config

alias Sanbase.Alert.Job
alias Sanbase.Alert.Trigger
alias Sanbase.Notifications.EmailNotifier

config :sanbase, Sanbase.Alerts.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  timeout: 30_000,
  overlap: false,
  jobs: [
    freeze_user_alerts: [
      schedule: "0 5 * * *",
      task: {Job, :freeze_alerts, []}
    ],
    unfreeze_user_alerts: [
      schedule: "0 10 * * *",
      task: {Job, :unfreeze_alerts, []}
    ],
    raw_signal_alert: [
      schedule: "1-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.RawSignalTriggerSettings]}
    ],
    screener_sonar_alert: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.ScreenerTriggerSettings]}
    ],
    eth_wallet_alert: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.EthWalletTriggerSettings]}
    ],
    wallet_movement_alert: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.WalletTriggerSettings]}
    ],
    wallet_usd_valuation_alert: [
      # Run the alert every 15 minutes as it's heavier to compute. Also, address
      # USD valuations do not change drastically that often.
      schedule: "4-59/15 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.WalletUsdValuationTriggerSettings]}
    ],
    wallet_assets_held_alert: [
      # Run the alert every 15 minutes as it's heavier to compute. Also, address
      # assets held do not change drastically that often.
      schedule: "5-59/15 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.WalletAssetsHeldTriggerSettings]}
    ],
    trending_words_sonar_alert: [
      schedule: "4-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.TrendingWordsTriggerSettings]}
    ],
    metric_alert: [
      schedule: "5-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.MetricTriggerSettings]}
    ],
    daily_metric_alert: [
      schedule: "0 3 * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.DailyMetricTriggerSettings]}
    ]
  ]

config :sanbase, Sanbase.Scrapers.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  timeout: 30_000,
  overlap: false,
  jobs: [
    update_api_call_limit_plans: [
      schedule: "@daily",
      task: {Sanbase.ApiCallLimit.Sync, :run, []}
    ],
    sync_products_with_stripe: [
      schedule: "@reboot",
      task: {Sanbase.Billing, :sync_products_with_stripe, []}
    ],
    sync_stripe_subscriptions: [
      schedule: "2-59/20 * * * *",
      task: {Sanbase.Billing, :sync_stripe_subscriptions, []}
    ],
    remove_duplicate_subscriptions: [
      schedule: "*/20 * * * *",
      task: {Sanbase.Billing, :remove_duplicate_subscriptions, []}
    ],
    create_free_basic_api: [
      schedule: "*/5 * * * *",
      task: {Sanbase.Billing, :create_free_basic_api, []}
    ],
    delete_free_basic_api: [
      schedule: "00 22 * * *",
      task: {Sanbase.Billing, :delete_free_basic_api, []}
    ],
    logo_fetcher: [
      schedule: "@daily",
      task: {Sanbase.ExternalServices.Coinmarketcap.LogoFetcher, :run, []}
    ],
    sync_events_from_intercom: [
      schedule: "00 10 * * *",
      task: {Sanbase.Intercom.UserEvent, :sync_events_from_intercom, []}
    ],
    sync_subscribed_users_with_changed_email: [
      schedule: "20 * * * *",
      task: {Sanbase.Accounts.User, :sync_subscribed_users_with_changed_email, []}
    ],
    update_all_uniswap_san_staked_users: [
      schedule: "4-59/30 * * * *",
      task: {Sanbase.Accounts.User.UniswapStaking, :update_all_uniswap_san_staked_users, []}
    ],
    sync_liquidity_subscriptions_staked_users: [
      schedule: "7-59/30 * * * *",
      task: {Sanbase.Billing, :sync_liquidity_subscriptions_staked_users, []}
    ],
    sync_stripe_transactions: [
      schedule: "30 00 * * *",
      task: {Sanbase.Billing.StripeSync, :run, []}
    ],
    intercom_to_kafka: [
      schedule: "30 01 * * *",
      task: {Sanbase.Intercom, :intercom_to_kafka, []}
    ],
    sync_newly_registered_to_intercom: [
      schedule: "30 03 * * *",
      task: {Sanbase.Intercom, :sync_newly_registered_to_intercom, []}
    ],
    sync_stripe_attributes_to_intercom: [
      schedule: "@daily",
      task: {Sanbase.Intercom.StripeAttributes, :run, []}
    ],
    sync_coinmarketcap_projects: [
      # When a new project gets a coinmarketcap string slug associated with it,
      # it is not until the first scrape which includes it, that it also gets the
      # coinmarketcap integer id. We're only scraping the top 2500 projects as
      # this is the limit our current paid plan allows if we scrape every 5 minutes.
      # Scraping once a day all projects will fill those missing coinmarketcap
      # integer ids.
      schedule: "@daily",
      task: {Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, :work, [[projects_number: 5_000]]}
    ],
    autogenerated_social_volume_query: [
      schedule: "15 * * * *",
      task: {Sanbase.Project.SocialVolumeQuery.CronJob, :run, []}
    ],
    scrape_cryptocompare_market_pairs: [
      schedule: "@daily",
      task: {Sanbase.Cryptocompare.Markets.Scraper, :run, []}
    ],
    fill_project_coinmarketcap_id_field: [
      schedule: "@hourly",
      task: {Sanbase.Project.Jobs, :fill_coinmarketcap_id, []}
    ],
    move_finished_oban_jobs: [
      timeout: :infinity,
      # run once every 6 hours
      schedule: "0 */6 * * *",
      task: {Sanbase.Cryptocompare.Jobs, :move_finished_jobs, []}
    ],
    comments_notification: [
      schedule: "0 18 * * *",
      task: {Sanbase.Comments.Notification, :notify_users, []}
    ],
    san_burn_credit_transaction: [
      schedule: "@hourly",
      task: {Sanbase.Billing.Subscription.SanBurnCreditTransaction, :run, []}
    ],
    sync_subscription_timeseries_stripe: [
      schedule: "10 01 * * *",
      task: {Sanbase.Billing.Subscription.Timeseries, :run, []}
    ],
    sync_nft_subscriptions: [
      schedule: "9-59/10 * * * *",
      task: {Sanbase.Billing.Subscription.NFTSubscription, :run, []}
    ],
    manage_postgres_index2: [
      schedule: "10 * * * *",
      task: {Sanbase.DiscordBot.AiServer, :manage_postgres_index2, []}
    ],
    renew_available_metrics_slugs: [
      schedule: "@daily",
      task: {Sanbase.AvailableMetrics, :update_all, []}
    ],
    send_daily_digest_metric_created: [
      schedule: "0 18 * * *",
      task: {EmailNotifier, :send_daily_digest, ["metric_created"]}
    ],
    send_daily_digest_metric_deleted: [
      schedule: "0 18 * * *",
      task: {EmailNotifier, :send_daily_digest, ["metric_deleted"]}
    ]
  ]
