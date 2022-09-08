import Config

config :sanbase, SanbaseWeb.Guardian,
  issuer: "santiment",
  secret_key: {SanbaseWeb.Guardian, :get_config, [:secret_key_base]}

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email"]},
    twitter: {Ueberauth.Strategy.Twitter, []}
  ]

config :guardian, Guardian.DB,
  repo: Sanbase.Repo,
  schema_name: "guardian_tokens",
  token_types: ["refresh"],
  sweep_interval: 20

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {System, :get_env, ["GOOGLE_OAUTH_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GOOGLE_OAUTH_CLIENT_SECRET"]}

config :ueberauth, Ueberauth.Strategy.Twitter.OAuth,
  consumer_key: {System, :get_env, ["TWITTER_OAUTH_CONSUMER_KEY"]},
  consumer_secret: {System, :get_env, ["TWITTER_OAUTH_CONSUMER_SECRET"]}
