# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :sanbase, Sanbase.Notifications.PriceVolumeDiff,
  webhook_url: {:system, "PRICE_VOLUME_DIFF_WEBHOOK_URL"},
  window_type: {:system, "PRICE_VOLUME_DIFF_WINDOW_TYPE"},
  approximation_window: {:system, "PRICE_VOLUME_DIFF_APPROXIMATION_WINDOW", "14"},
  comparison_window: {:system, "PRICE_VOLUME_DIFF_COMPARISON_WINDOW", "7"},
  notification_threshold: {:system, "PRICE_VOLUME_DIFF_NOTIFICATION_THRESHOLD", "0.01"},
  notification_volume_threshold:
    {:system, "PRICE_VOLUME_DIFF_NOTIFICATION_VOLUME_THRESHOLD", "100000"},
  notifications_cooldown: {:system, "PRICE_VOLUME_DIFF_NOTIFICATIONS_COOLDOWN", "86400"},
  debug_url: {:system, "PRICE_VOLUME_DIFF_DEBUG_URL"},
  notifications_enabled: {:system, "PRICE_VOLUME_DIFF_NOTIFICATIONS_ENABLED", false}

config :sanbase, Sanbase.Notifications.Insight,
  webhook_url: {:system, "INSIGHTS_DISCORD_WEBHOOK_URL"},
  insights_discord_publish_user: {:system, "INSIGHTS_DISCORD_PUBLISH_USER", "New Insight"}

config :sanbase, Sanbase.Notifications.Discord.DaaSignal,
  webhook_url: {:system, "DAA_SIGNAL_DISCORD_WEBHOOK_URL"},
  publish_user: {:system, "DAA_SIGNAL_DISCORD_PUBLISH_USER", "Daily Active Addresses Going Up"},
  trading_volume_threshold: {:system, "DAA_SIGNAL_TRADING_VOLUME_THRESHOLD", "100000"},
  timeframe_from: {:system, "DAA_SIGNAL_TIMEFRAME_FROM", "31"},
  timeframe_to: {:system, "DAA_SIGNAL_TIMEFRAME_TO", "1"},
  change: {:system, "DAA_SIGNAL_CHANGE", "3"},
  # cooldown for 6 hours for project
  project_cooldown: {:system, "DAA_SIGNAL_PROJECT_COOLDOWN", "21600"}

config :sanbase, Sanbase.Notifications.Discord.ExchangeInflow,
  webhook_url: {:system, "EXCHANGE_INFLOW_DISCORD_WEBHOOK_URL"},
  trading_volume_threshold: {:system, "EXCHANGE_INFLOW_TRADING_VOLUME_THRESHOLD", "100000"},
  publish_user:
    {:system, "EXCHANGE_INFLOW_DISCORD_PUBLISH_USER", "Tokens Moved Into An Exchange"},
  signal_trigger_percent: {:system, "EXCHANGE_INFLOW_TRIGER_PERCENT", "1"},
  ethereum_signal_trigger_percent: {:system, "EXCHANGE_INFLOW_ETHEREUMTRIGER_PERCENT", "0.4"},
  interval_days: {:system, "EXCHANGE_INFLOW_INTERVAL_DAYS", "1"},
  cooldown_days: {:system, "EXCHANGE_INFLOW_COOLDOWN_DAYS", "1"}

config :sanbase, Sanbase.Telegram,
  api_base_url: "https://api.telegram.org/bot",
  bot_username: {:system, "TELEGRAM_NOTIFICATAIONS_BOT_USERNAME", "SanbaseSignalsStageBot"},
  telegram_endpoint: {:system, "TELEGRAM_ENDPOINT_RANDOM_STRING", "some_random_string"},
  token: {:system, "TELEGRAM_SIGNALS_BOT_TOKEN"}

config :sanbase, Sanbase.Scheduler,
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
      task: {Sanbase.Signals.Scheduler, :run_price_volume_difference_signals, []}
    ],
    daily_active_addresses_sonar_signal: [
      schedule: "2-59/5 * * * *",
      task: {Sanbase.Signals.Scheduler, :run_daily_active_addresses_signals, []}
    ],
    price_percent_change_sonar_singal: [
      schedule: "3-59/5 * * * *",
      task: {Sanbase.Signals.Scheduler, :run_price_percent_change_signals, []}
    ],
    price_absolute_change_sonar_singal: [
      schedule: "4-59/5 * * * *",
      task: {Sanbase.Signals.Scheduler, :run_price_absolute_change_signals, []}
    ],
    trending_words_sonar_singal: [
      schedule: "5-59/5 * * * *",
      task: {Sanbase.Signals.Scheduler, :run_trending_words_signals, []}
    ]
  ]
