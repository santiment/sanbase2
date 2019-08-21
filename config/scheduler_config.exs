# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

alias Sanbase.Signal.Trigger

config :sanbase, Sanbase.Signals.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  global: true,
  timeout: 30_000,
  jobs: [
    daa_discord_signal: [
      schedule: "*/5 * * * *",
      task: {Sanbase.Notifications.Discord.DaaSignal, :run, []}
    ],
    exchange_inflow_discord_signal: [
      schedule: "1-59/5 * * * *",
      task: {Sanbase.Notifications.Discord.ExchangeInflow, :run, []}
    ],
    price_volume_difference_sonar_signal: [
      schedule: "1-59/5 * * * *",
      task:
        {Sanbase.Signal.Scheduler, :run_signal, [Trigger.PriceVolumeDifferenceTriggerSettings]}
    ],
    daily_active_addresses_sonar_signal: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.DailyActiveAddressesSettings]}
    ],
    price_percent_change_sonar_signal: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.PricePercentChangeSettings]}
    ],
    price_absolute_change_sonar_signal: [
      schedule: "4-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.PriceAbsoluteChangeSettings]}
    ],
    eth_wallet_signal: [
      schedule: "4-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.MetricTriggerSettings]}
    ],
    trending_words_sonar_signal: [
      schedule: "5-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.TrendingWordsTriggerSettings]}
    ],
    metric_signal: [
      schedule: "6-59/5 * * * *",
      task: {Sanbase.Signal.Scheduler, :run_signal, [Trigger.EthWalletTriggerSettings]}
    ]
  ]

config :sanbase, Sanbase.Scrapers.Scheduler,
  scheduler_enabled: {:system, "QUANTUM_SCHEDULER_ENABLED", false},
  global: true,
  timeout: 30_000,
  jobs: [
    sync_stripe_subscriptions: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Billing.Subscription, :sync_all, []}
    ],
    logo_fetcher: [
      schedule: "@daily",
      task: {Sanbase.ExternalServices.Coinmarketcap.LogoFetcher, :run, []}
    ]
  ]
