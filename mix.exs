defmodule Sanbase.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sanbase,
      name: "Sanbase",
      version: "0.0.1",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
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
      homepage_url: "https://sanbase-low.santiment.net/projects"
    ]
  end

  def application do
    [
      mod: {Sanbase.Application, []},
      extra_applications: [:logger, :runtime_tools, :sasl, :clickhousex],
      included_applications: [:oauther, :brod, :kaffe]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  # local_dev/ dir is used for local development and is excluded from source control
  defp elixirc_paths(:dev), do: ["lib", "local_dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:absinthe_metrics, "~> 1.0"},
      {:absinthe_phoenix, github: "absinthe-graphql/absinthe_phoenix", override: true},
      {:absinthe_plug, github: "absinthe-graphql/absinthe_plug", override: true},
      {:absinthe, github: "absinthe-graphql/absinthe", override: true},
      {:arc, git: "https://github.com/marinho10/arc"},
      {:async_with, github: "fertapric/async_with"},
      {:basic_auth, "~> 2.2"},
      {:clickhouse_ecto, git: "https://github.com/santiment/clickhouse_ecto"},
      {:con_cache, "~> 0.13"},
      {:corsica, "~> 1.0"},
      {:cowboy, "~> 2.0"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:csv, "~> 2.1"},
      {:dataloader, "~> 1.0.0"},
      {:decimal, "~> 1.0"},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false},
      {:distillery, "~> 2.0", runtime: false},
      {:earmark, "~> 1.2"},
      {:ecto_enum, "~> 1.3"},
      {:elasticsearch, "~> 1.0"},
      {:envy, "~> 1.1.1", only: [:dev, :test]},
      {:erlex, "~> 0.2.6", override: true},
      {:ex_admin, github: "santiment/ex_admin"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_machina, "~> 2.2", only: [:dev, :test]},
      {:ex_queb, "~> 1.0"},
      {:ex_unit_notifier, "~> 0.1", only: :test},
      {:excoveralls, "~> 0.8", optional: true, only: [:dev, :test]},
      {:exprof, "~> 0.2.0"},
      {:extwitter, "~> 0.9.0"},
      {:faker, "~> 0.12"},
      {:floki, "~> 0.20"},
      {:gettext, "~> 0.11"},
      {:guardian, "~> 2.0"},
      {:hackney, github: "benoitc/hackney", override: true},
      {:hammer, "~> 6.0"},
      {:httpoison, "~> 1.2", override: true},
      {:inflex, "~> 2.0", override: true},
      {:instream, "~> 0.16"},
      {:jason, "~> 1.1"},
      {:kaffe, github: "santiment/kaffe", override: true},
      {:kafka_protocol, github: "qzhuyan/kafka_protocol", branch: "lz4-nif", override: true},
      {:libcluster, "~> 3.0"},
      {:lz4b, "0.0.4"},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false},
      {:mock, "~> 0.3"},
      {:mockery, "~> 2.2"},
      {:mogrify, "~> 0.7.2"},
      {:number, "~> 1.0"},
      {:observer_cli, "~> 1.3"},
      {:phoenix_ecto, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.1", only: :dev},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix, "~> 1.4.3"},
      {:plug_cowboy, "~> 2.0"},
      {:poison, ">= 1.0.0"},
      {:postgrex, ">= 0.0.0"},
      {:prometheus_ecto, "~> 1.3"},
      {:prometheus_ex, "~> 3.0", override: true},
      {:prometheus_plugs, "~> 1.0"},
      {:quantum, "~> 2.3"},
      {:remote_ip, "~> 0.1"},
      {:rexbug, ">= 1.0.0"},
      {:san_exporter_ex, github: "santiment/san-exporter-ex"},
      {:sentry, "~> 7.0"},
      {:stream_data, "~> 0.4.2", only: :test},
      {:stripity_stripe, git: "https://github.com/code-corps/stripity_stripe"},
      {:sweet_xml, "~> 0.6"},
      {:temp, "~> 0.4"},
      {:tesla, "~> 1.0"},
      {:timex_ecto, "~> 3.3.0"},
      {:timex, "~> 3.5.0"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.8.0", override: true}
    ]
  end

  defp aliases() do
    [
      "ecto.setup": [
        "load_dotenv",
        "ecto.drop -r Sanbase.Repo",
        "ecto.create -r Sanbase.Repo",
        "ecto.load -r Sanbase.Repo"
      ],
      "ecto.migrate": [
        "load_dotenv",
        "ecto.migrate -r Sanbase.Repo",
        "ecto.dump -r Sanbase.Repo"
      ],
      "ecto.gen.migration": [
        "ecto.gen.migration -r Sanbase.Repo"
      ],
      "ecto.rollback": [
        "load_dotenv",
        "ecto.rollback -r Sanbase.Repo",
        "ecto.dump -r Sanbase.Repo"
      ],
      test: [
        "load_dotenv",
        "ecto.create -r Sanbase.Repo --quiet",
        "ecto.load -r Sanbase.Repo",
        "test"
      ],

      # Append `_all` so the Ecto commands apply to all repos.
      # and run all tests
      "ecto.setup_all": [
        "load_dotenv",
        "ecto.drop",
        "ecto.create",
        "ecto.load"
      ],
      "ecto.load_all": [
        "load_dotenv",
        "ecto.create --quiet",
        "ecto.load"
      ],
      "ecto.reset_all": [
        "load_dotenv",
        "ecto.drop",
        "ecto.setup_all"
      ],
      "ecto.migrate_all": [
        "load_dotenv",
        "ecto.migrate",
        "ecto.dump"
      ],
      "ecto.rollback_all": [
        "load_dotenv",
        "ecto.rollback",
        "ecto.dump"
      ]
    ]
  end
end
