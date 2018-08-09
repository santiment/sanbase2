defmodule Sanbase.ClickhouseRepo do
  use Ecto.Repo, otp_app: :sanbase

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Utils.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_DATABASE_URL"))

    {:ok, opts}
  end

  @doc ~s"""
  For performance reasons, `WHERE` should be replaced with `PREWHERE`.
  This cannot be done with Ecto expressions. Because of that we're converting the
  query to a string and replacing the words.
  Executing raw SQL will return a map with `columns`, `command`, `num_rows` and `rows`
  that should be manually transformed to the needed struct
  """
  defmacro all_prewhere(query, transform_fn \\ nil) do
    quote bind_quoted: [query: query, transform_fn: transform_fn] do
      require Sanbase.ClickhouseRepo
      alias Sanbase.ClickhouseRepo
      {query, args} = Ecto.Adapters.SQL.to_sql(:all, ClickhouseRepo, query)

      query = query |> String.replace(" WHERE ", " PREWHERE ")

      ClickhouseRepo.query(query, args)
      |> case do
        {:ok, result} ->
          transform_fn = transform_fn || (&ClickhouseRepo.load(__MODULE__, {result.columns, &1}))

          result =
            Enum.map(
              result.rows,
              transform_fn
            )

          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defmacro query_transform(query, args, transform_fn \\ nil) do
    quote bind_quoted: [query: query, args: args, transform_fn: transform_fn] do
      require Sanbase.ClickhouseRepo, as: ClickhouseRepo

      ClickhouseRepo.query(query, args)
      |> case do
        {:ok, result} ->
          transform_fn = transform_fn || (&ClickhouseRepo.load(__MODULE__, {result.columns, &1}))

          result =
            Enum.map(
              result.rows,
              transform_fn
            )

          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc ~s"""
  For performance reasons, `WHERE` should be replaced with `PREWHERE`.
  This cannot be done with Ecto expressions. Because of that we're converting the
  query to a string and replacing the words.
  Executing raw SQL will return a map with `columns`, `command`, `num_rows` and `rows`
  that should be manually transformed to the needed struct
  """
  defmacro all_prewhere(query, transform_fn \\ nil) do
    quote bind_quoted: [query: query, transform_fn: transform_fn] do
      require Sanbase.ClickhouseRepo
      alias Sanbase.ClickhouseRepo
      {query, args} = Ecto.Adapters.SQL.to_sql(:all, ClickhouseRepo, query)

      query = query |> String.replace(" WHERE ", " PREWHERE ")

      ClickhouseRepo.query(query, args)
      |> case do
        {:ok, result} ->
          transform_fn = transform_fn

          result =
            Enum.map(
              result.rows,
              &ClickhouseRepo.load(__MODULE__, {result.columns, &1})
            )

          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Private functions and macros

  defmacro query_transform(repo, query, args, transform_fn) do
    quote bind_quoted: [repo: repo, query: query, args: args, transform_fn: transform_fn] do
    end
  end
end
