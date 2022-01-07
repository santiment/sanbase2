# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :sanbase, Sanbase.Notifications.Insight,
  enabled: {:system, "INSIGHTS_DISCORD_NOTIFICATION_ENABLED", "true"},
  webhook_url: {:system, "INSIGHTS_DISCORD_WEBHOOK_URL"},
  insights_discord_publish_user: {:system, "INSIGHTS_DISCORD_PUBLISH_USER", "New Insight"}

config :sanbase, Sanbase.Telegram,
  bot_username: {:system, "TELEGRAM_NOTIFICATAIONS_BOT_USERNAME", "SantimentSignalsStageBot"},
  telegram_endpoint: {:system, "TELEGRAM_ENDPOINT_RANDOM_STRING", "some_random_string"},
  token: {:system, "TELEGRAM_SIGNALS_BOT_TOKEN"}

config :sanbase, Sanbase.Alert, email_channel_enabled: {:system, "EMAIL_CHANNEL_ENABLED", "false"}

config :sanbase, Sanbase.Notifications.Discord.Bot,
  bot_secret: {:system, "DISCORD_BOT_SECRET", ""}
