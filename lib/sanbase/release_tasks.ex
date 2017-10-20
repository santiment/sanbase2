defmodule Sanbase.ReleaseTasks do

  @start_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto
  ]

  def repos, do: Application.get_env(:sanbase, :ecto_repos, [])

  def migrate do
    # Load the code for myapp, but don't start it
    :ok = Application.load(:sanbase)

    IO.puts "Starting dependencies.."
    # Start apps necessary for executing migrations
    Enum.each(@start_apps, &Application.ensure_all_started/1)

    # Start the Repo(s) for myapp
    IO.puts "Starting repos.."
    Enum.each(repos(), &(&1.start_link(pool_size: 1)))

    # Run migrations
    Enum.each(repos(), &run_migrations_for/1)

    # Signal shutdown
    IO.puts "Success!"
    :init.stop()
  end

  def priv_dir(app), do: "#{:code.priv_dir(app)}"

  defp run_migrations_for(repo) do
    app = Keyword.get(repo.config, :otp_app)
    IO.puts "Running migrations for #{app}"
    Ecto.Migrator.run(repo, migrations_path(repo), :up, all: true)
  end

  def migrations_path(repo), do: priv_path_for(repo, "migrations")

  def priv_path_for(repo, filename) do
    app = Keyword.get(repo.config, :otp_app)
    repo_underscore = repo |> Module.split |> List.last |> Macro.underscore
    Path.join([priv_dir(app), repo_underscore, filename])
  end
end
