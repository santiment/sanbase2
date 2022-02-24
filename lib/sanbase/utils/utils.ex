defmodule Sanbase.Utils do
  require Sanbase.Utils.Config, as: Config

  @prod_db_patterns ["amazonaws"]
  def prod_db?() do
    database_url = System.get_env("DATABASE_URL")

    database_hostname = Config.module_get(Sanbase.Repo, :hostname)

    prod_db_url? =
      not is_nil(database_url) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_url, &1))

    prod_db_config? =
      not is_nil(database_hostname) and
        Enum.any?(@prod_db_patterns, &String.contains?(database_hostname, &1))

    prod_db_url? or prod_db_config?
  end
end
