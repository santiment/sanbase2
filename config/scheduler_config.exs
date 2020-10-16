# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

alias Sanbase.Signal.Trigger

config :sanbase, Sanbase.Signals.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  timeout: 30_000,
  jobs: [
    price_volume_difference_sonar_signal: [
      schedule: "1-59/5 * * * *",
      task:
        {Sanbase.Signal.Scheduler, :run_signal, [Trigger.PriceVolumeDifferenceTriggerSettings]}
    ],
    screener_sonar_signal: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.ScreenerTriggerSettings]}
    ],
    eth_wallet_signal: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.EthWalletTriggerSettings]}
    ],
    wallet_movement: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.WalletTriggerSettings]}
    ],
    trending_words_sonar_signal: [
      schedule: "4-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.TrendingWordsTriggerSettings]}
    ],
    metric_signal: [
      schedule: "5-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.MetricTriggerSettings]}
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
    sync_plans_in_stripe: [
      schedule: "@reboot",
      task: {Sanbase.Billing.Plan, :sync_plans_in_stripe, []}
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
      task: {Sanbase.Auth.UserSettings, :sync_paid_with, []}
    ]
  ]
