defmodule Mix.Tasks.CloneMetricRegistry do
  @shortdoc "Make sure the destructive operations are not executed on production databases"

  @moduledoc """
  #{@shortdoc}

  Check the MIX_ENV environment variable, the DATABASE_URL environment variable and
  the database configuration to determine if the operation is executed in dev
  or test environment against a production database.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    file = Path.join([__DIR__, "metric_registry_pg_dump.sql"])
    db_url = Keyword.get(opts, :database_url) |> String.replace_prefix("ecto://", "postgres://")

    try do
      {"", 0} =
        System.cmd(
          "pg_dump",
          [
            "--data-only",
            "--table=metric_registry",
            "--file=#{file}",
            "--dbname=#{db_url}",
            # So it can be used by pg_restore
            # "--format=custom",
            "--inserts"
          ]
        )

      contents = File.read!(file)
      contents = String.replace(contents, "sanbase2.metric_registry", "public.metric_registry")
      File.write!(file, contents)

      System.cmd(
        "psql",
        [
          "--dbname=sanbase_dev",
          "--file=#{file}",
          "--echo-all"
        ]
      )
    after
      File.rm!(file)
    end

    :ok
  end

  defp parse_args(args) do
    {options, _, _} =
      OptionParser.parse(args, strict: [database_url: :string, drop_existing: :boolean])

    options
  end
end
