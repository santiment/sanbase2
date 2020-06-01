defmodule Sanbase.Repo do
  use Ecto.Repo, otp_app: :sanbase, adapter: Ecto.Adapters.Postgres
  use Scrivener, page_size: 10

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("DATABASE_URL"))

    {:ok, opts}
  end
end
