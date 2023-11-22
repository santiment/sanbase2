[
  inputs: [
    "config/*.{ex,exs}",
    "lib/*.{ex,exs}",
    "lib/**/*.{ex,exs}",
    "test/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "priv/**/*.{ex,exs}",
    "mix.exs",
    ".formatter.exs"
  ],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
