defmodule Sanbase.Queries.Executor.Result do
  @moduledoc ~s"""
  The result of computing an SQL query.
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
  # The input comes from the client, so it is a decompression-bomb vector: a few
  # MB of gzip can inflate to GBs and exhaust the node's memory. Both the
  # encoded input and the decompressed output are capped. A cacheable result is
  # at most 500KB compressed (see `Sanbase.Queries.Cache`), so these limits are
  # far above any legitimate value.
  @max_encoded_bytes 10 * 1024 * 1024
  @max_decompressed_bytes 50 * 1024 * 1024
  @invalid_gzip_error "The provided value is not a valid gzip binary"

  @spec decode_and_decompress(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def decode_and_decompress(base64_gzip, opts \\ []) when is_binary(base64_gzip) do
    max_encoded = Keyword.get(opts, :max_encoded_bytes, @max_encoded_bytes)
    max_decompressed = Keyword.get(opts, :max_decompressed_bytes, @max_decompressed_bytes)

    with :ok <- check_encoded_size(base64_gzip, max_encoded),
         {:ok, gzip} <- decode64(base64_gzip) do
      bounded_gunzip(gzip, max_decompressed)
    end
  end

  defp check_encoded_size(data, max_bytes) when byte_size(data) <= max_bytes, do: :ok

  defp check_encoded_size(_data, max_bytes) do
    {:error, "The provided value is over the limit of #{format_bytes(max_bytes)}"}
  end

  defp decode64(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, "The provided value is not a valid base64-encoded binary"}
    end
  end

  # Inflate chunk by chunk with `:zlib.safeInflate/2`, stopping as soon as the
  # output goes over `max_bytes`, instead of `:zlib.gunzip/1`, which inflates
  # everything into memory first.
  defp bounded_gunzip(gzip, max_bytes) do
    z = :zlib.open()

    try do
      # windowBits 16 + 15: expect a gzip header and trailer. `:reset` decodes every
      # member of a concatenated gzip, like `:zlib.gunzip/1` (`:cut` keeps only the
      # first). The output limit is checked across all members.
      :ok = :zlib.inflateInit(z, 31, :reset)
      inflate_chunks(z, :zlib.safeInflate(z, gzip), [], 0, max_bytes)
    rescue
      _e in [ErlangError] -> {:error, @invalid_gzip_error}
    after
      :zlib.close(z)
    end
  end

  defp inflate_chunks(z, {status, output}, acc, size, max_bytes) do
    output_size = IO.iodata_length(output)
    size = size + output_size

    cond do
      size > max_bytes ->
        {:error, "The decompressed value is over the limit of #{format_bytes(max_bytes)}"}

      # `:finished` only means the input was consumed. `inflateEnd/1` raises
      # `data_error` (rescued above) if the gzip stream did not actually end,
      # i.e. the input was truncated.
      status == :finished ->
        :ok = :zlib.inflateEnd(z)
        {:ok, IO.iodata_to_binary(Enum.reverse([output | acc]))}

      # Empty output is not a sign of truncation: a long gzip header is consumed
      # without producing any. Truncation is caught by `inflateEnd/1` above.
      status == :continue ->
        inflate_chunks(z, :zlib.safeInflate(z, []), [output | acc], size, max_bytes)
    end
  end

  defp inflate_chunks(_z, _other, _acc, _size, _max_bytes), do: {:error, @invalid_gzip_error}

  defp format_bytes(bytes) when bytes >= 1024 * 1024, do: "#{div(bytes, 1024 * 1024)}MB"
  defp format_bytes(bytes), do: "#{bytes} bytes"

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

  # These fields are fields of the Result struct, but are not needed when checking
  # if the compressed and encoded result for the cache are provided
  @skippable_fields [:compressed_rows]
  def all_fields_present?(%__MODULE__{} = result) do
    nil_fields =
      result
      |> Map.from_struct()
      # The frontend won't provide compressed rows when caching the query,
      # so if it's missing it should be ok.
      |> Map.filter(fn {k, v} -> is_nil(v) and k not in @skippable_fields end)
      |> Enum.map(fn {k, _v} -> Sanbase.Utils.Inflect.camelize(k, :lower) end)
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
      map_with_underscore_keys =
        Map.new(map, fn {k, v} -> {Sanbase.Utils.Inflect.underscore(k), v} end)

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
