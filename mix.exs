defmodule Sanbase.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sanbase,
      name: "Sanbase",
      version: "0.0.1",
      elixir: "~> 1.6",
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

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Sanbase.Application, []},
      extra_applications: [:logger, :runtime_tools, :sasl],
      included_applications: [:faktory_worker_ex, :oauther]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_ecto, "~> 3.2"},
      {:postgrex, ">= 0.0.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:decimal, "~> 1.0"},
      {:reverse_proxy, git: "https://github.com/slogsdon/elixir-reverse-proxy"},
      {:corsica, "~> 1.0", only: [:dev]},
      {:tesla, "~> 0.9.0"},
      {:poison, ">= 1.0.0"},
      {:instream, "~> 0.16"},
      {:hammer, "~> 5.0"},
      {:ex_admin, github: "smpallen99/ex_admin", branch: "master"},
      {:basic_auth, "~> 2.2"},
      {:mockery, "~> 2.2"},
      {:distillery, "~> 1.5", runtime: false},
      {:timex, "~> 3.0"},
      {:timex_ecto, "~> 3.0"},
      {:hackney, "~> 1.10"},
      {:guardian, "~> 1.0"},
      {:absinthe_ecto, "~> 0.1.0"},
      {:absinthe_plug, "~> 1.4.0"},
      {:faktory_worker_ex, git: "https://github.com/santiment/faktory_worker_ex"},
      {:temp, "~> 0.4"},
      {:httpoison, "~> 0.13"},
      {:floki, "~> 0.20"},
      {:sentry, "~> 6.0.4"},
      {:extwitter, "~> 0.9.0"},
      {:envy, "~> 1.1.1", only: [:dev, :test]},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, "~> 0.6"},
      {:ex_unit_notifier, "~> 0.1", only: :test},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false},
      {:dataloader, "~> 1.0.0"},
      {:csv, "~> 2.1"},
      {:arc, git: "https://github.com/marinho10/arc"},
      {:uuid, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.1", only: :dev},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:con_cache, "~> 0.13"},
      {:excoveralls, "~> 0.8", optional: true, only: [:dev, :test]},
      {:observer_cli, "~> 1.3"},
      {:plug_attack, "~> 0.3.1"},
      {:earmark, "~> 1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["load_dotenv", "ecto.create", "ecto.load", "run priv/repo/seeds.exs"],
      "ecto.reset": ["load_dotenv", "ecto.drop", "ecto.setup"],
      "ecto.migrate": ["load_dotenv", "ecto.migrate", "ecto.dump"],
      "ecto.rollback": ["load_dotenv", "ecto.rollback", "ecto.dump"],
      test: ["load_dotenv", "ecto.create --quiet", "ecto.load", "test"]
    ]
  end
end
