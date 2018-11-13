defmodule Sanbase.TimescaleRepo do
  use Ecto.Repo, otp_app: :sanbase
  use Scrivener, page_size: 10

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  TIMESCALE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Utils.Math.to_integer()

    System.put_env(
      "TIMESCALE_DATABASE_URL",
      "ecto://postgres:postgres@timescaledb-postgresql.default.svc.cluster.local:5432/etherbi"
    )

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("TIMESCALE_DATABASE_URL"))

    {:ok, opts}
  end
end
