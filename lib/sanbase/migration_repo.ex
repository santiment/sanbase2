defmodule Sanbase.MigrationRepo do
  use Ecto.Repo, otp_app: :sanbase, adapter: Ecto.Adapters.Postgres

  require Sanbase.Utils.Config, as: Config
  @database_url_env_var_name "DATABASE_URL_MIGRATIONS_USER"
  def database_url_env_var(), do: @database_url_env_var_name

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()
    max_overflow = Config.get(:max_overflow) |> Sanbase.Math.to_integer()

    # The migrations sometimes need privileges that are not granted to the
    # user that queries the database. These privileges include creation of
    # new schemas and creation of new types.
    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env(@database_url_env_var_name))

    {:ok, opts}
  end
end
