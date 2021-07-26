defmodule Sanbase.ReleaseTasks.Migrate do
  def repos(), do: Application.get_env(:sanbase, :ecto_repos, [])

  def migrate do
    IO.puts("Start migrations...")

    for repo <- repos() do
      IO.puts("Running migrations for #{inspect(repo)}")
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      IO.puts("Finished running migrations for #{inspect(repo)}")
    end
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end
end
