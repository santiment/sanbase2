defmodule Mix.Tasks.DatabaseSafety do
  @shortdoc "Make sure the destructive operations are not executed on production databases"

  @moduledoc """
  #{@shortdoc}

  Check the MIX_ENV environment variable, the DATABASE_URL environment variable and
  the database configuration to determine if the operation is executed in dev
  or test environment against a production database.
  """

  use Mix.Task
  require Sanbase.Utils.Config, as: Config

  @prod_db_patterns ["amazonaws"]

  @impl Mix.Task
  def run(_args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    else
      raise(Mix.Error, "Cannot load Envy")
    end

    env = Config.module_get(Sanbase, :env)
    database_url = System.get_env(Sanbase.MigrationRepo.database_url_env_var())

    database_hostname = Config.module_get(Sanbase.Repo, :hostname)

    prod_db_url? =
      not is_nil(database_url) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_url, &1))

    prod_db_config? =
      not is_nil(database_hostname) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_hostname, &1))

    case env != :prod and (prod_db_url? or prod_db_config?) do
      true ->
        raise(Mix.Error, """
        Migration execution was stopped due to safety concerns!

        Trying to execute a migration against a production database while not in
        production environment is prohibited. Either the DATABASE_URL or the
        Sanbase.Repo config value for :hostname is pointing to a production database.

        DATABASE_URL takes precedence over the config file but even if the config
        file points to production and the DATABASE_URL env var does not, this would
        still raise an error
        """)

      false ->
        :ok
    end
  end
end
