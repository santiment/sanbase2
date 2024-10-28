defmodule Sanbase.Repo do
  use Ecto.Repo, otp_app: :sanbase, adapter: Ecto.Adapters.Postgres

  alias Sanbase.Utils.Config

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.module_get(__MODULE__, :pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("DATABASE_URL"))

    test_env? = Application.get_env(:sanbase, :env) == :test

    opts =
      if is_nil(System.get_env("DATABASE_URL")) or test_env? do
        opts
      else
        opts
        |> Keyword.put(:ssl, true)
        |> Keyword.put(:ssl_opts, verify: :verify_none)
      end

    {:ok, opts}
  end
end
