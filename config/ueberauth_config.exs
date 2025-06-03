import Config

config :sanbase, SanbaseWeb.Guardian,
  issuer: "santiment",
  secret_key: {SanbaseWeb.Guardian, :get_config, [:secret_key_base]}

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email"]},
    twitter: {Sanbase.Ueberauth.Strategy.Twitter, []}
  ]

config :guardian, Guardian.DB,
  repo: Sanbase.Repo,
  schema_name: "guardian_tokens",
  token_types: ["refresh"],
  sweep_interval: 20

# The rest of the config is in runtime.exs so the env vars can be read on runtime
