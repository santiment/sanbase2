# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

alias Sanbase.Alert.Trigger

config :sanbase, Sanbase.Alerts.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  timeout: 30_000,
  overlap: false,
  jobs: [
    # Enable the freezing cron job only after the frontend handles the frozen alerts
    # freeze_user_alerts: [
    #   schedule: "0 5 * * *",
    #   task: {Sanbase.Alert.Job, :freeze_alerts, []}
    # ],
    price_volume_difference_sonar_alert: [
      schedule: "1-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.PriceVolumeDifferenceTriggerSettings]}
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
    wallet_movement: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.WalletTriggerSettings]}
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
    notify_users_for_comments: [
      schedule: "@hourly",
      task: {Sanbase.Comments.Notification, :notify_users, []}
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
    send_weekly_monitor_watchlist_digest: [
      schedule: "@weekly",
      task: {Sanbase.UserList.Monitor, :run, []}
    ],
    sync_users_to_intercom: [
      schedule: "00 01 * * *",
      task: {Sanbase.Intercom, :sync_users, []}
    ],
    # It should be scheduled after sync_users_to_intercom job so it gets up to date data
    sync_intercom_to_kafka: [
      schedule: "00 16 * * *",
      task: {Sanbase.Intercom, :sync_intercom_to_kafka, []}
    ],
    sync_events_from_intercom: [
      schedule: "00 10 * * *",
      task: {Sanbase.Intercom.UserEvent, :sync_events_from_intercom, []}
    ],
    sync_newsletter_subscribers_to_mailchimp: [
      schedule: "@daily",
      task: {Sanbase.Email.Mailchimp, :run, []}
    ],
    sync_paid_with: [
      schedule: "20 * * * *",
      task: {Sanbase.Accounts.UserSettings, :sync_paid_with, []}
    ],
    sync_subscribed_users_with_changed_email: [
      schedule: "20 * * * *",
      task: {Sanbase.Accounts.User, :sync_subscribed_users_with_changed_email, []}
    ],
    update_all_uniswap_san_staked_users: [
      schedule: "4-59/30 * * * *",
      task: {Sanbase.Accounts.User, :update_all_uniswap_san_staked_users, []}
    ],
    sync_liquidity_subscriptions_staked_users: [
      schedule: "7-59/30 * * * *",
      task: {Sanbase.Billing, :sync_liquidity_subscriptions_staked_users, []}
    ],
    sync_coinmarketcap_projects: [
      # When a new project gets a coinmarketcap string slug associated with it,
      # it is not until the first scrape which includes it, that it also gets the
      # coinmarketcap integer id. We're only scraping the top 2500 projects as
      # this is the limit our current paid plan allows if we scrape every 5 minutes.
      # Scraping once a day all projects will fill those missing coinmarketcap
      # integer ids.
      schedule: "@daily",
      task:
        {Sanbase.ExternalServices.Coinmarketcap.TickerFetcher, :work, [projects_number: 5_000]}
    ],
    autogenerated_social_volume_query: [
      schedule: "15 * * * *",
      task: {Sanbase.Model.Project.SocialVolumeQuery.CronJob, :run, []}
    ],
    warm_up_wallet_hunters: [
      # fetch proposals count to warm up infura cache
      schedule: "@minutely",
      task: {Sanbase.WalletHunters.Contract, :wallet_proposals_count, []}
    ],
    poll_pending_wallet_hunters_proposal_transactions: [
      schedule: "5 * * * *",
      task: {Sanbase.WalletHunters.Proposal, :poll_pending_transactions, []}
    ],
    update_earned_relays: [
      schedule: "8 * * * *",
      task: {Sanbase.WalletHunters.Proposal, :update_earned_relays, []}
    ],
    poll_pending_wallet_hunters_vote_transactions: [
      schedule: "6 * * * *",
      task: {Sanbase.WalletHunters.Vote, :poll_pending_transactions, []}
    ],
    scrape_cryptocompare_market_pairs: [
      schedule: "@daily",
      task: {Sanbase.Cryptocompare.Markets.Scraper, :run, []}
    ],
    fill_project_coinmarketcap_id_field: [
      schedule: "@hourly",
      task: {Sanbase.Model.Project.Jobs, :fill_coinmarketcap_id, []}
    ],
    move_finished_oban_jobs: [
      timeout: :infinity,
      # run once every 6 hours
      schedule: "0 */6 * * *",
      task: {Sanbase.Cryptocompare.Jobs, :move_finished_jobs, []}
    ]
  ]
