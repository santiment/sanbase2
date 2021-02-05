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
  jobs: [
    price_volume_difference_sonar_alert: [
      schedule: "1-59/5 * * * *",
      task: {Sanbase.Alert.Scheduler, :run_alert, [Trigger.PriceVolumeDifferenceTriggerSettings]}
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
  jobs: [
    notify_users_for_comments: [
      schedule: "@hourly",
      task: {Sanbase.Comments.Notification, :notify_users, []}
    ],
    send_email_on_trial_day: [
      schedule: "00 07 * * *",
      task: {Sanbase.Billing.Subscription.SignUpTrial, :send_email_on_trial_day, []}
    ],
    update_finished_trials: [
      schedule: "*/10 * * * *",
      task: {Sanbase.Billing.Subscription.SignUpTrial, :update_finished, []}
    ],
    cancel_prematurely_ended_trials: [
      schedule: "*/5 * * * *",
      task: {Sanbase.Billing.Subscription.SignUpTrial, :cancel_prematurely_ended_trials, []}
    ],
    sync_with_stripe: [
      schedule: "@reboot",
      task: {Sanbase.Billing, :sync_with_stripe, []}
    ],
    sync_stripe_subscriptions: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Billing.Subscription, :sync_all, []}
    ],
    cancel_about_to_expire_trials: [
      schedule: "3-59/30 * * * *",
      task: {Sanbase.Billing.Subscription, :cancel_about_to_expire_trials, []}
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
      schedule: "00 15 * * *",
      task: {Sanbase.Intercom, :sync_users, []}
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
    get_kaiko_realtime_prices: [
      # Start scraping at every round minute
      schedule: "* * * * *",
      task: {Sanbase.Kaiko, :run, []}
    ],
    get_kaiko_realtime_prices_30: [
      # Start scraping at every minute and 30 seconds.
      # Cron jobs do not support sub-minute frequency, so it is done by starting
      # at every round minute and sleeping for 30 seconds before doing the work.
      schedule: "* * * * *",
      task: {Sanbase.Kaiko, :run, [[sleep: 30_000]]}
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
    ]
  ]
