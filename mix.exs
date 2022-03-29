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
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ],
      source_url: "https://github.com/santiment/sanbase2/",
      homepage_url: "https://app.santiment.net/projects",
      # Supress errors that should not be shown
      xref: [exclude: [Oban]],
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
      included_applications: [:oauther, :brod, :kaffe, :ueberauth_twitter]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]

  # local_dev/ dir is used for local development and is excluded from source control
  defp elixirc_paths(:dev), do: ["lib", "local_dev", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:absinthe_metrics, "~> 1.1"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe, "~> 1.5"},
      {:async_with, github: "fertapric/async_with"},
      {:browser, "~> 0.4.4"},
      {:cidr, "~> 1.1"},
      {:clickhouse_ecto, github: "santiment/clickhouse_ecto", branch: "migrate-ecto-3"},
      {:clickhousex, github: "santiment/clickhousex", override: true},
      {:con_cache, "~> 1.0"},
      {:corsica, "~> 1.0"},
      {:cowboy, "~> 2.0"},
      {:crc32cer, github: "zmstone/crc32cer", override: true},
      {:credo, "~> 1.6.0-rc.1", only: [:dev, :test], runtime: false},
      {:csv, "~> 2.1"},
      {:csvlixir, "~> 2.0", override: true},
      {:dataloader, "~> 1.0.0"},
      {:db_connection, "~> 2.2", override: true},
      {:decimal, "~> 1.0"},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:distillery, "~> 2.0", runtime: false},
      {:earmark, "~> 1.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.3"},
      {:ecto_sql, "~> 3.6"},
      {:ecto, "~> 3.6"},
      {:envy, "~> 1.1.1", only: [:dev, :test]},
      # TODO: Remove after the OTP 24 version is released
      {:jose, github: "potatosalad/erlang-jose", override: true},
      {:erlex, "~> 0.2.6", override: true},
      {:ethereumex, "~> 0.7.0"},
      {:event_bus, "~> 1.6.2"},
      {:ex_abi, "~> 0.5.4"},
      {:ex_admin, github: "santiment/ex_admin"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      # TODO: Move back to hex once the OTP 24 version is released
      {:ex_keccak, github: "tzumby/ex_keccak", override: true},
      {:ex_machina, "~> 2.2", only: [:dev, :test]},
      {:ex_unit_notifier, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.8", optional: true, only: [:test]},
      {:expletive, "~> 0.1.0"},
      {:exprof, "~> 0.2.0"},
      {:extwitter, "~> 0.11"},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:floki, "~> 0.20"},
      {:gettext, "~> 0.11"},
      {:guardian_db, "~> 2.0"},
      {:guardian, "~> 2.0"},
      {:hackney, "~> 1.17", override: true},
      {:hammer, "~> 6.0"},
      {:httpoison, "~> 1.2", override: true},
      {:inch_ex, github: "rrrene/inch_ex", only: [:dev, :test]},
      {:inflex, "~> 2.0", override: true},
      {:instream, "~> 0.16"},
      {:jason, "~> 1.2"},
      {:kaffe, github: "santiment/kaffe", override: true},
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
      {:number, "~> 1.0"},
      # TODO: Go back to original once https://github.com/lexmag/oauther/pull/22 is merged
      {:oauther, github: "tobstarr/oauther", override: true},
      {:oban, "~> 2.7"},
      {:observer_cli, "~> 1.3"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 3.0", override: true},
      {:phoenix_live_dashboard, "~> 0.3"},
      {:phoenix_live_reload, "~> 1.1", only: :dev},
      {:phoenix_live_view, "~> 0.14"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix, "~> 1.6.0"},
      {:plug_cowboy, "~> 2.0"},
      {:postgrex, "~> 0.15.0", override: true},
      {:prometheus_ecto, "~> 1.3"},
      {:prometheus_ex, "~> 3.0", override: true},
      {:prometheus_plugs, "~> 1.0"},
      {:quantum, "~> 3.0"},
      {:remote_ip, "~> 1.0"},
      {:rexbug, ">= 1.0.0"},
      {:san_exporter_ex, github: "santiment/san-exporter-ex"},
      {:sentry, "~> 7.0"},
      {:snappyer, github: "zmstone/snappyer", override: true},
      {:stream_data, "~> 0.5", only: :test},
      {:stripity_stripe, "~> 2.9"},
      {:sweet_xml, "~> 0.6"},
      {:telemetry_metrics, "~> 0.5"},
      {:telemetry_poller, "~> 0.4"},
      {:temp, "~> 0.4"},
      {:tesla, "~> 1.0"},
      {:timex, "~> 3.5.0"},
      {:ueberauth_google, "~> 0.10"},
      {:ueberauth_twitter, github: "santiment/ueberauth_twitter"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.9", override: true},
      {:waffle, "~> 1.1"},
      {:websockex, "~> 0.4.3"},
      {:kaffy, github: "santiment/kaffy"}
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
