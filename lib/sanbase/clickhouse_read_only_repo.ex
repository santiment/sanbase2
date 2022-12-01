defmodule Sanbase.ClickhouseRepo.ReadOnly do
  @moduledoc ~s"""
  Clickhouse repo with read-only access.

  This module defines a clickhouse repo that is started with read-only
  credentials.
  It does not define any of the query functions as it is not indended to be
  used directly. Instead, in the process that requires read-only restricted
  access, the repo is put as the dynamic repo with the following code:
  `Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)`
  After that, the user can execute queries written by the user using the same
  ClickhouseRepo functions, but the connection pool used is the one configured
  by this module
  """
  env = Mix.env()

  default_dynamic_repo =
    if env == :test, do: Sanbase.ClickhouseRepo, else: Sanbase.Clickhouse.ReadOnly

  adapter = if env == :test, do: Ecto.Adapters.Postgres, else: ClickhouseEcto

  use Ecto.Repo,
    otp_app: :sanbase,
    adapter: adapter,
    read_only: true,
    default_dynamic_repo: default_dynamic_repo

  require Sanbase.Utils.Config, as: Config

  def init(_, opts) do
    pool_size =
      Config.module_get(__MODULE__, :pool_size)
      |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_READONLY_DATABASE_URL"))

    {:ok, opts}
  end
end
