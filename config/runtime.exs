import Config

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")
  parity_url = System.get_env("PARITY_URL")

  config :sanbase2, SanbaseWeb.Endpoint,
    url: [host: host, port: port],
    http: [
      port: port,
      protocol_options: [
        max_header_name_length: 64,
        max_header_value_length: 8192,
        max_request_line_length: 16_384,
        max_headers: 100
      ]
    ],
    secret_key_base: secret_key_base,
    server: true,
    cache_static_manifest: "priv/static/cache_manifest.json",
    root: ".",
    version: Application.spec(:sanbase, :vsn),
    load_from_system_env: true,
    check_origin: ["//*.santiment.net", "//*.sanr.app"]

  config :ethereumex,
    url: parity_url,
    http_options: [timeout: 25_000, recv_timeout: 25_000],
    http_headers: [{"Content-Type", "application/json"}]
end
