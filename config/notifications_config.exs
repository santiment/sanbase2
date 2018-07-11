# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :sanbase, Sanbase.Notifications.CheckPrices,
  webhook_url: {:system, "CHECK_PRICES_WEBHOOK_URL"},
  notification_channel: {:system, "CHECK_PRICES_CHANNEL", "#signals-stage"},
  slack_notifications_enabled: {:system, "CHECK_PRICES_NOTIFICATIONS_ENABLED", false}

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
