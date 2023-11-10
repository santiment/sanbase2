[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  subdirectories: ["priv/*/migrations"]
]
