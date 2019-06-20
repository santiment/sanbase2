use Mix.Config

config :sanbase, Sanbase.StripeConfig, api_key: {:system, "STRIPE_SECRET_KEY", ""}

config :stripity_stripe,
  api_key: {Sanbase.StripeConfig, :api_key, []},
  json_library: Jason
