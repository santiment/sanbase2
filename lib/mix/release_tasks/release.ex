defmodule Sanbase.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :sanbase

  # TODO: Check if we can remove this
  @start_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto,
    :ecto_sql
  ]

  def migrate do
    load_app()

    IO.puts("Run migrations: UP")

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    IO.puts("Run migrations: rollback")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    IO.puts("Loading sanbase app...")
    Application.load(@app)

    IO.puts("Starting required dependencies to run the migrations...")
    Enum.each(@start_apps, &Application.ensure_all_started/1)
  end
end
