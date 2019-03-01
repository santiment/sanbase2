defmodule Sanbase.TimescaleRepo do
  use Ecto.Repo, otp_app: :sanbase
  use Scrivener, page_size: 10

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  TIMESCALE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("TIMESCALE_DATABASE_URL"))

    {:ok, opts}
  end
end
