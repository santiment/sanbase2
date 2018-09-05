defmodule Sanbase.TimescaleRepo do
  use Ecto.Repo, otp_app: :sanbase
  use Scrivener, page_size: 10

  @doc """
  Dynamically loads the repository url from the
  TIMESCALE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, System.get_env("TIMESCALE_DATABASE_URL"))}
  end
end
