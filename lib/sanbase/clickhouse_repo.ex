defmodule Sanbase.ClickhouseRepo do
  use Ecto.Repo, otp_app: :sanbase

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_DATABASE_URL"))

    {:ok, opts}
  end

  defmacro query_transform(query, args, transform_fn \\ nil) do
    quote bind_quoted: [query: query, args: args, transform_fn: transform_fn] do
      try do
        require Sanbase.ClickhouseRepo, as: ClickhouseRepo

        ClickhouseRepo.query(query, args)
        |> case do
          {:ok, result} ->
            transform_fn =
              transform_fn || (&ClickhouseRepo.load(__MODULE__, {result.columns, &1}))

            result =
              Enum.map(
                result.rows,
                transform_fn
              )

            {:ok, result}

          {:error, error} ->
            {:error, error}
        end
      rescue
        e ->
          {:error, "Cannot execute ClickHouse query. Reason: " <> Exception.message(e)}
      end
    end
  end
end
