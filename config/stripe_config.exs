import Config

config :sanbase, Sanbase.Billing.DiscordNotification,
  payments_webhook_url: {:system, "STRIPE_PAYMENT_DISCORD_WEBHOOK"},
  failed_payments_webhook_url: {:system, "STRIPE_FAILED_PAYMENT_DISCORD_WEBHOOK"},
  payment_action_required_webhook_url: {:system, "STRIPE_PAYMENT_ACTION_REQUIRED_DISCORD_WEBHOOK"},
  publish_user: {:system, "STRIPE_PAYMENT_DISCORD_PUBLISH_USER", "Stripe Payments Bot"}

config :sanbase, Sanbase.StripeConfig, api_key: {:system, "STRIPE_SECRET_KEY", ""}
config :sanbase, SanbaseWeb.Plug.VerifyStripeWebhook, webhook_secret: {:system, "STRIPE_WEBHOOK_SECRET", ""}

config :stripity_stripe,
  api_key: {Sanbase.StripeConfig, :api_key, []},
  json_library: Jason
