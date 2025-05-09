defmodule Sanbase.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sanbase,
      name: "Sanbase",
      version: "0.0.1",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # source_url: "https://github.com/santiment/sanbase2/",
      homepage_url: "https://app.santiment.net/projects",
      # Supress errors that should not be shown
      xref: [exclude: [Oban]],
      dialyzer: [
        plt_ignore_apps: [:stripity_stripe]
      ]
    ]
  end

  def application do
    [
      mod: {Sanbase.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :sasl,
        :clickhousex,
        :os_mon,
        :event_bus
      ],
      included_applications: [:brod, :ueberauth_twitter, :nostrum]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]

  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe, "~> 1.5"},
      {:brod, "~> 4.0"},
      {:browser, "~> 0.5"},
      {:cachex, "~> 3.4"},
      {:cidr, "~> 1.1"},
      {:clickhouse_ecto, github: "santiment/clickhouse_ecto", branch: "migrate-ecto-3"},
      {:clickhousex, github: "santiment/clickhousex", override: true},
      {:con_cache, "~> 1.0"},
      {:cowboy, "~> 2.0"},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      {:crc32cer, github: "zmstone/crc32cer", override: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dataloader, "~> 2.0.0"},
      {:db_connection, "~> 2.2", override: true},
      {:decimal, "~> 2.1"},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:earmark, "~> 1.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.3"},
      {:ecto_sql, "~> 3.12"},
      {:ecto, "~> 3.12"},
      {:envy, "~> 1.1.1", only: [:dev, :test]},
      {:erlex, "~> 0.2.6"},
      {:ethereumex, "~> 0.9"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:event_bus, "~> 1.7.0"},
      {:ex_abi, "~> 0.6"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_ses, "~> 2.4"},
      {:gen_smtp, "~> 1.2"},
      {:ex_json_schema, "~> 0.10.2"},
      {:ex_keccak, "~> 0.7"},
      {:ex_machina, "~> 2.2", only: [:dev, :test]},
      {:ex_unit_notifier, "~> 1.0", only: :test},
      {:expletive, "~> 0.1.0"},
      {:exprof, "~> 0.2.0"},
      {:extwitter, "~> 0.12"},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:finch, "~> 0.18"},
      {:floki, "~> 0.20"},
      {:fuzzy_compare, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:guardian_db, "~> 3.0"},
      {:guardian, "~> 2.3.2"},
      {:gun, "~> 2.0", hex: :remedy_gun, override: true},
      {:hackney, "~> 1.17", override: true},
      {:hammer, "~> 6.0"},
      {:httpoison, "~> 2.0", override: true},
      {:html_sanitize_ex, "~> 1.4"},
      {:inflex, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:kino_db, "~> 0.2.2"},
      {:kino_vega_lite, "~> 0.1.9"},
      {:libcluster, "~> 3.0"},
      {:libcluster_postgres, "~> 0.1"},
      {:map_diff, "~> 1.3"},
      {:mint, "~> 1.0"},
      {:mock, "~> 0.3"},
      {:mockery, "~> 2.2"},
      {:mogrify, "~> 0.8"},
      {:mutex, "~> 3.0"},
      {:mochiweb, "~> 3.2"},
      {:neuron, "~> 5.0", only: :dev},
      {:nimble_csv, "~> 1.1"},
      {:nimble_parsec, "~> 1.4"},
      {:norm, "~> 0.12"},
      {:nostrum, github: "Kraigie/nostrum"},
      {:number, "~> 1.0"},
      {:oauther, "~> 1.3"},
      {:oban, "~> 2.7"},
      {:observer_cli, "~> 1.3"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.3"},
      {:phoenix_live_reload, "~> 1.1", only: :dev},
      {:phoenix_live_view, "~> 1.0.1", override: true},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix, "~> 1.7.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, "~> 0.19"},
      {:prom_ex, "~> 1.8"},
      {:quantum, "~> 3.0"},
      {:remote_ip, "~> 1.0"},
      {:rexbug, ">= 1.0.0"},
      {:rustler, "~> 0.24"},
      {:scribe, "~> 0.11"},
      {:sentry, "~> 10.0"},
      {:stream_data, "~> 1.1", only: :test, override: true},
      {:stripity_stripe, "~> 3.2"},
      {:sweet_xml, "~> 0.6"},
      {:swoosh, "~> 1.7"},
      {:table_rex, "~> 4.0"},
      {:telemetry, "~> 1.1", override: true},
      {:temp, "~> 0.4"},
      {:tesla, "~> 1.0"},
      {:timex, "~> 3.7"},
      {:ueberauth_google, "~> 0.10"},
      {:ueberauth_twitter, "~> 0.4"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.9", override: true},
      {:waffle, "~> 1.1"},
      {:websockex, "~> 0.4.3"},
      {:mox, "~> 1.2"},
      {:ex_audit, "~> 0.10.0"}
    ]
  end

  defp aliases() do
    [
      "ecto.load": [
        "load_dotenv",
        "database_safety",
        "ecto.load -r Sanbase.Repo"
      ],
      "ecto.create": [
        "load_dotenv",
        "database_safety",
        "ecto.create -r Sanbase.Repo"
      ],
      "ecto.drop": [
        "load_dotenv",
        "database_safety",
        "ecto.drop -r Sanbase.Repo"
      ],
      "ecto.setup": [
        "load_dotenv",
        "database_safety",
        "ecto.drop -r Sanbase.Repo",
        "ecto.create -r Sanbase.Repo",
        "ecto.load -r Sanbase.Repo"
      ],
      "ecto.migrate": [
        "load_dotenv",
        "database_safety",
        "ecto.migrate -r Sanbase.Repo",
        "ecto.dump -r Sanbase.Repo"
      ],
      "ecto.gen.migration": [
        "ecto.gen.migration -r Sanbase.Repo"
      ],
      "ecto.rollback": [
        "load_dotenv",
        "database_safety",
        "ecto.rollback -r Sanbase.Repo",
        "ecto.dump -r Sanbase.Repo"
      ],
      "hex.outdated": [
        "hex.outdated --sort status"
      ],
      test: [
        "load_dotenv",
        "database_safety",
        "ecto.create -r Sanbase.Repo --quiet",
        "ecto.load -r Sanbase.Repo --skip-if-loaded",
        "run test/test_seeds.exs",
        "test"
      ]
    ] ++
      [
        # esbuild/assets building related
        setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
        "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
        "assets.build": ["tailwind default", "esbuild default"],
        "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
      ]
  end
end
