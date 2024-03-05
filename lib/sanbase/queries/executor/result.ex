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

  @doc ~s"""
  Accept a binary that is a base64-encoded gzip binary, and return
  the decoded and decompressed value

  In order to reduce the size of data sent from the frontend to the backend
  when storing cached values.
  """
  @spec decode_and_decompress(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def decode_and_decompress(base64_gzip) when is_binary(base64_gzip) do
    with {:ok, gzip} <- Base.decode64(base64_gzip),
         decompressed when is_binary(decompressed) <- :zlib.gunzip(gzip) do
      {:ok, decompressed}
    else
      :error ->
        {:error, "The provided value is not a valid base64-encoded binary"}
    end
  rescue
    _e in [ErlangError] ->
      {:error, "The provided value is not a valid gzip binary"}
  end

  def compress_and_encode(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Jason.encode!()
    |> :zlib.gzip()
    |> Base.encode64()
  end

  @doc ~s"""
  Accept a string that is a stringified JSON object representing the result
  of executing an SQL query, and return a `Result` struct.
  The GraphQL API uses snake_case internally, but the JS frontend uses camelCase,
  so the keys might be in any of those two formats. This function will handle
  both cases.
  """
  @spec from_json_string(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_json_string(json) do
    # map_from_json/1 will also convert all keys to snake_case
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

  def all_fields_present?(%__MODULE__{} = result) do
    nil_fields =
      result
      |> Map.from_struct()
      # The frontend won't provide compressed rows when caching the query,
      # so if it's missing it should be ok.
      |> Map.filter(fn {k, v} -> is_nil(v) and k != :compressed_rows end)
      |> Enum.map(fn {k, _v} -> Inflex.camelize(k, :lower) end)
      |> Enum.sort()

    case nil_fields do
      [] ->
        true

      _ ->
        {:error, "The following result fields are not provided: #{Enum.join(nil_fields, ", ")}"}
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
    |> Plug.Crypto.non_executable_binary_to_term([:safe])
  end
end
