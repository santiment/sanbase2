defmodule Sanbase.Queries.Executor.Result do
  @moduledoc ~s"""
  The result of computing a dashboard panel SQL query.
  """

  @type t :: %__MODULE__{
          query_id: non_neg_integer(),
          clickhouse_query_id: String.t(),
          summary: Map.t(),
          rows: list(String.t() | number() | boolean() | DateTime.t()),
          compressed_rows: String.t(),
          columns: list(String.t()),
          column_types: list(String.t()),
          query_start_time: DateTime.t(),
          query_end_time: DateTime.t()
        }

  defstruct query_id: nil,
            clickhouse_query_id: nil,
            summary: nil,
            rows: nil,
            compressed_rows: nil,
            columns: nil,
            column_types: nil,
            query_start_time: nil,
            query_end_time: nil

  def compress_rows(rows) do
    rows
    |> :erlang.term_to_binary()
    |> :zlib.gzip()
    |> Base.encode64()
  end

  def decompress_rows(compressed_rows) do
    compressed_rows
    |> Base.decode64!()
    |> :zlib.gunzip()
    |> :erlang.binary_to_term()
  end
end
