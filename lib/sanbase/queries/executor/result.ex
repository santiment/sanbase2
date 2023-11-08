defmodule Sanbase.Queries.Executor.Result do
  @moduledoc ~s"""
  The result of computing a dashboard panel SQL query.
  """

  @type t :: %__MODULE__{
          query_id: non_neg_integer(),
          clickhouse_query_id: String.t(),
          summary: Map.t(),
          rows: list(String.t() | number() | boolean() | DateTime.t()),
          compressed_rows: String.t() | nil,
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

  def from_json_string(json) do
    case map_from_json(json) do
      {:ok, map} ->
        result = %__MODULE__{
          query_id: map["query_id"],
          clickhouse_query_id: map["clickhouse_query_id"],
          summary: map["summary"],
          rows: map["rows"],
          compressed_rows: map["compressed_rows"],
          columns: map["columns"],
          column_types: map["column_types"],
          query_start_time: map["query_start_time"],
          query_end_time: map["query_end_time"]
        }

        {:ok, result}

      {:error, error} ->
        {:error, "Provided JSON is malformed: #{inspect(error)}"}
    end
  end

  defp map_from_json(json) do
    with {:ok, map} <- Jason.decode(json) do
      # The JSON provided by the frontend to the API might include
      # keys like queryStartTime, queryEndTime, etc.
      map_with_underscore_keys = Map.new(map, fn {k, v} -> {Inflex.underscore(k), v} end)

      {:ok, map_with_underscore_keys}
    end
  end

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
