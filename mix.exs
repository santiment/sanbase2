defmodule Sanbase.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sanbase,
      name: "Sanbase",
      version: "0.0.1",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ],
      source_url: "https://github.com/santiment/sanbase2/",
      homepage_url: "https://app.santiment.net/projects",
      # Supress errors that should not be shown
      xref: [exclude: [Oban, ExAdmin]],
      dialyzer: [
        plt_ignore_apps: [:ex_admin, :stripity_stripe]
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
      included_applications: [:kaffe, :brod, :ueberauth_twitter, :nostrum]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(mix_env) when mix_env in [:dev, :test] do
    case System.get_env("ENABLE_EXADMIN_DASHBOARDS", "false") do
      "true" ->
        ["lib", "test/support"]

      "false" ->
        web_without_admin = Path.wildcard("lib/sanbase_web/*") -- ["lib/sanbase_web/admin"]

        ["lib/sanbase", "test/support", "lib/mix", "lib/sheets_templates"] ++ web_without_admin
    end
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe, "~> 1.5"},
      {:brod, "~> 3.8", manager: :rebar3, override: true},
      {:browser, "~> 0.5"},
      {:cachex, "~> 3.4"},
      {:cidr, "~> 1.1"},
      {:clickhouse_ecto, github: "santiment/clickhouse_ecto", branch: "migrate-ecto-3"},
      {:clickhousex, github: "santiment/clickhousex", override: true},
      {:con_cache, "~> 1.0"},
      {:corsica, "~> 1.0"},
      {:cowboy, "~> 2.0"},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      {:crc32cer, github: "zmstone/crc32cer", override: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.0"},
      {:csvlixir, "~> 2.0", override: true},
      {:dataloader, "~> 1.0.0"},
      {:db_connection, "~> 2.2", override: true},
      {:decimal, "~> 2.0", override: true},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:earmark, "~> 1.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.3"},
      {:ecto_sql, "~> 3.6"},
      {:ecto, "~> 3.6"},
      {:envy, "~> 1.1.1", only: [:dev, :test]},
      {:erlex, "~> 0.2.6", override: true},
      {:ethereumex, "~> 0.9"},
      {:event_bus, "~> 1.7.0"},
      {:ex_abi, "~> 0.6"},
      {:ex_admin, github: "santiment/ex_admin"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_json_schema, "~> 0.9.2"},
      {:ex_keccak, "~> 0.7"},
      {:ex_machina, "~> 2.2", only: [:dev, :test]},
      {:ex_unit_notifier, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.8", optional: true, only: [:test]},
      {:expletive, "~> 0.1.0"},
      {:exprof, "~> 0.2.0"},
      {:extwitter, "~> 0.12"},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:finch, "~> 0.12", override: true},
      {:floki, "~> 0.20"},
      {:gettext, "~> 0.11"},
      {:guardian_db, "~> 2.0"},
      {:guardian, "~> 2.0"},
      {:gun, "~> 2.0", hex: :remedy_gun, override: true},
      {:hackney, "~> 1.17", override: true},
      {:hammer, "~> 6.0"},
      {:httpoison, "~> 2.0", override: true},
      {:inch_ex, github: "rrrene/inch_ex", only: [:dev, :test]},
      {:inflex, "~> 2.0", override: true},
      {:jason, "~> 1.2"},
      {:jose, "~> 1.11"},
      {:kaffe, github: "santiment/kaffe", override: true},
      {:kaffy, github: "santiment/kaffy"},
      {:kafka_protocol,
       github: "santiment/kafka_protocol", branch: "working-version", override: true},
      {:libcluster, "~> 3.0"},
      {:lz4b, github: "santiment/lz4b"},
      {:mint, "~> 1.0"},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:mock, "~> 0.3"},
      {:mockery, "~> 2.2"},
      {:mogrify, "~> 0.8"},
      {:mutex, "~> 1.1"},
      {:neuron, "~> 5.0", only: :dev},
      {:nimble_csv, "~> 1.1"},
      {:norm, "~> 0.12"},
      {:nostrum, github: "Kraigie/nostrum"},
      {:number, "~> 1.0"},
      {:oauther, "~> 1.3"},
      {:oban, "~> 2.7"},
      {:observer_cli, "~> 1.3"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 3.0", override: true},
      {:phoenix_live_dashboard, "~> 0.3"},
      {:phoenix_live_reload, "~> 1.1", only: :dev},
      {:phoenix_live_view, "~> 0.14"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix, "~> 1.6.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, "~> 0.16", override: true},
      {:prom_ex, "~> 1.8"},
      {:quantum, "~> 3.0"},
      {:remote_ip, "~> 1.0"},
      {:rexbug, ">= 1.0.0"},
      {:rustler, "~> 0.24"},
      {:san_exporter_ex, github: "santiment/san-exporter-ex"},
      {:sentry, "~> 8.0"},
      {:snappyer, github: "zmstone/snappyer", override: true},
      {:stream_data, "~> 0.5", only: :test},
      {:stripity_stripe, "~> 2.9"},
      {:supervisor3, "~> 1.1", manager: :rebar3, override: true},
      {:sweet_xml, "~> 0.6"},
      {:swoosh, "~> 1.7"},
      {:table_rex, "~> 3.1"},
      {:telemetry_metrics, "~> 0.5"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry, "~> 1.1", override: true},
      {:temp, "~> 0.4"},
      {:tesla, "~> 1.0"},
      {:timex, "~> 3.7"},
      {:ueberauth_google, "~> 0.10"},
      {:ueberauth_twitter, "~> 0.4"},
      {:uniq, "~> 0.5"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.9", override: true},
      {:waffle, "~> 1.1"},
      {:websockex, "~> 0.4.3"},
      {:poison, "~> 5.0"}
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
      test: [
        "load_dotenv",
        "database_safety",
        "ecto.create -r Sanbase.Repo --quiet",
        "ecto.load -r Sanbase.Repo --skip-if-loaded",
        "test"
      ]
    ]
  end
end
