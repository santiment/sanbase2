[
  inputs: [
    "config/*.{ex,exs}",
    "lib/*.{ex,exs,heex}",
    "lib/**/*.{ex,exs,heex}",
    "test/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "priv/**/*.{ex,exs}",
    "mix.exs",
    ".formatter.exs"
  ],
  import_deps: [:phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
