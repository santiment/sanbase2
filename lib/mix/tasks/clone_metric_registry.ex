defmodule Mix.Tasks.CloneMetricRegistry do
  @shortdoc "Make sure the destructive operations are not executed on production databases"

  @moduledoc """
  #{@shortdoc}

  Copies the `metric_registry` table from a source database into the local
  `sanbase_dev` database. The source is dumped read-only (`pg_dump --data-only
  --inserts`); only the local database is ever written to.

  ## Usage

      mix clone_metric_registry --database-url=<SOURCE_DB_URL> [--drop-existing]

  Options:

    * `--database-url` (required) — connection URL of the source database to
      dump the `metric_registry` table from. Read-only on the source. The
      underscore form `--database_url` is also accepted.

    * `--drop-existing` — TRUNCATE the local `metric_registry` table before
      loading. Required for a clean reload: the dump uses `--inserts` with
      explicit ids, so loading on top of existing rows raises duplicate-key
      errors. This is destructive and is guarded to run ONLY against the local
      dev database — see `ensure_local_drop_allowed!/0`. It refuses to run when
      `MIX_ENV=prod`, when the `DATABASE_URL` env var is set (a deployed
      environment), or when `Sanbase.Repo` is not pointed at a local host.

  After loading, call `Sanbase.Metric.Registry.refresh_stored_terms/0` (or
  restart the server) so the in-memory metric mapsets pick up the new rows.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)

    # Fail fast before doing any work if a destructive drop was requested in an
    # environment where it is not allowed.
    drop_existing? = Keyword.get(opts, :drop_existing, false)
    if drop_existing?, do: ensure_local_drop_allowed!()

    file = Path.join([__DIR__, "metric_registry_pg_dump.sql"])
    db_url = source_db_url!(opts)

    try do
      {"", 0} =
        System.cmd(
          "pg_dump",
          [
            "--data-only",
            "--table=metric_registry",
            "--file=#{file}",
            "--dbname=#{db_url}",
            # `--column-inserts` (rather than `--inserts`) emits the column names
            # in each INSERT, so the load is independent of the physical column
            # order. The source and local tables have the same columns but in a
            # different order (migrations added them in a different sequence), and
            # positional inserts would misalign the values.
            "--column-inserts"
          ]
        )

      contents = File.read!(file)
      contents = String.replace(contents, "sanbase2.metric_registry", "public.metric_registry")

      # The dump is `--data-only --inserts` with explicit ids, so loading it on
      # top of existing rows raises duplicate-key errors. When `--drop-existing`
      # is passed, wipe the local table first for a clean reload. The TRUNCATE is
      # destructive, so it is only ever allowed against the local dev database.
      contents =
        if drop_existing? do
          "TRUNCATE public.metric_registry RESTART IDENTITY CASCADE;\n\n" <> contents
        else
          contents
        end

      File.write!(file, contents)

      # --single-transaction + ON_ERROR_STOP make the load all-or-nothing: any
      # failed statement (including the optional TRUNCATE) aborts the whole
      # load instead of leaving the table half-populated.
      {_output, exit_status} =
        System.cmd(
          "psql",
          [
            "--dbname=sanbase_dev",
            "--file=#{file}",
            "--echo-all",
            "--single-transaction",
            "--set=ON_ERROR_STOP=1",
            # Silence the TRUNCATE ... CASCADE NOTICE noise so a successful run
            # does not read like a failure.
            "--set=client_min_messages=warning"
          ]
        )

      if exit_status != 0 do
        Mix.raise(
          "Failed to load the metric_registry dump into sanbase_dev (psql exit #{exit_status})."
        )
      end

      Mix.shell().info([:green, "\nSUCCESS: metric_registry loaded into sanbase_dev.", :reset])

      Mix.shell().info(
        "Run `Sanbase.Metric.Registry.refresh_stored_terms()` (or restart the server) " <>
          "so the in-memory metric mapsets pick up the new rows."
      )
    after
      File.rm!(file)
    end

    :ok
  end

  defp parse_args(args) do
    {options, _, _} =
      args
      |> normalize_switches()
      |> OptionParser.parse(strict: [database_url: :string, drop_existing: :boolean])

    options
  end

  # OptionParser only matches the hyphenated switch form (`--database-url`); the
  # underscore form is reported as invalid. Accept the underscore form too by
  # rewriting just the switch token (never the value after `=`).
  defp normalize_switches(args) do
    Enum.map(args, fn
      "--database_url" -> "--database-url"
      "--database_url=" <> value -> "--database-url=" <> value
      other -> other
    end)
  end

  defp source_db_url!(opts) do
    case Keyword.get(opts, :database_url) do
      url when is_binary(url) and url != "" ->
        String.replace_prefix(url, "ecto://", "postgres://")

      _ ->
        Mix.raise(
          "Missing required --database-url. Usage: " <>
            "mix clone_metric_registry --database-url=<SOURCE_DB_URL> [--drop-existing]"
        )
    end
  end

  # The destructive TRUNCATE may run against the local dev database only. Refuse
  # in any deployed (stage/prod) environment. Each of these independently marks a
  # deployed environment:
  #   * MIX_ENV is prod
  #   * the DATABASE_URL env var is set (only deployed environments set it; local
  #     dev hardcodes the connection in config/dev.exs)
  #   * Sanbase.Repo is not pointed at a local host
  defp ensure_local_drop_allowed!() do
    cond do
      Mix.env() == :prod ->
        Mix.raise("Refusing to drop: MIX_ENV is prod. --drop-existing is local-dev only.")

      System.get_env("DATABASE_URL") not in [nil, ""] ->
        Mix.raise(
          "Refusing to drop: the DATABASE_URL env var is set, indicating a deployed " <>
            "(stage/prod) environment. --drop-existing only wipes the local dev database."
        )

      not local_repo?() ->
        Mix.raise(
          "Refusing to drop: Sanbase.Repo host #{inspect(repo_hostname())} is not local. " <>
            "--drop-existing is local-dev only."
        )

      true ->
        :ok
    end
  end

  defp local_repo?(), do: repo_hostname() in ["localhost", "127.0.0.1", "::1", nil]

  defp repo_hostname() do
    Application.get_env(:sanbase, Sanbase.Repo, []) |> Keyword.get(:hostname)
  end
end
