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
  threshold: {:system, "DAA_SIGNAL_THRESHOLD", "100"},
  timeframe_from: {:system, "DAA_SIGNAL_TIMEFRAME_FROM", "30"},
  timeframe_to: {:system, "DAA_SIGNAL_TIMEFRAME_TO", "2"},
  change: {:system, "DAA_SIGNAL_CHANGE", "3"}

config :sanbase, Sanbase.Notifications.Discord.ExchangeInflow,
  webhook_url: {:system, "EXCHANGE_INFLOW_DISCORD_WEBHOOK_URL"},
  publish_user: {:system, "DAA_SIGNAL_DISCORD_PUBLISH_USER", "DAA GOING UP"},
  signal_trigger_percent: {:system, "EXCHANGE_INFLOW_TRIGER_PERCEN", "1"},
  interval_days: {:system, "EXCHANGE_INFLOW_INTERVAL_DAYS", "1"}
