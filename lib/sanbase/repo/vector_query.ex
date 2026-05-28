defmodule Sanbase.Repo.VectorQuery do
  @moduledoc """
  Drop-in replacement for `Sanbase.Repo.all/2` for queries whose params
  contain large embedding vectors (pgvector cosine searches).

  Ecto's default query logger inspects every parameter; for a 1536-dim
  embedding that produces tens of KB of float noise per query. This
  wrapper suppresses the default log and emits a single debug line with
  timing, row count, SQL, and parameters with long lists collapsed to
  `<vec dim=N head=[...] ...>`.
  """

  require Logger

  alias Sanbase.Repo

  @vector_head_sample 4
  @vector_min_len 16

  @spec all(Ecto.Queryable.t(), keyword()) :: list()
  def all(query, opts \\ []) do
    opts = Keyword.put(opts, :log, false)
    start_mono = System.monotonic_time()
    result = Repo.all(query, opts)

    took_ms =
      System.convert_time_unit(System.monotonic_time() - start_mono, :native, :millisecond)

    Logger.debug(fn ->
      {sql, params} = Repo.to_sql(:all, query)
      truncated = Enum.map(params, &truncate_param/1)
      "QUERY OK db=#{took_ms}ms rows=#{length(result)} #{sql} #{inspect(truncated)}"
    end)

    result
  end

  defp truncate_param(list) when is_list(list) and length(list) >= @vector_min_len do
    head = Enum.take(list, @vector_head_sample)
    "<vec dim=#{length(list)} head=#{inspect(head)} ...>"
  end

  defp truncate_param(other), do: other
end
