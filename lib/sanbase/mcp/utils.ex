defmodule Sanbase.MCP.Utils do
  @moduledoc """
  Common utility functions for MCP tools.
  """

  @doc """
  Parses a time period string and returns a {from_datetime, to_datetime} tuple.

  ## Examples

      iex> Sanbase.MCP.Utils.parse_time_period("1h", ~U[2025-09-10 00:00:00Z])
      {:ok, {~U[2025-09-09 23:00:00Z], ~U[2025-09-10 00:00:00Z]}}

      iex> Sanbase.MCP.Utils.parse_time_period("invalid")
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
  """
  @spec parse_time_period(String.t(), DateTime.t()) ::
          {:ok, {DateTime.t(), DateTime.t()}} | {:error, String.t()}
  def parse_time_period(time_period, now \\ DateTime.utc_now()) do
    # The now parameter allows for deterministic testing by providing a fixed reference time instead of using the current system time.
    if Sanbase.DateTimeUtils.valid_interval?(time_period) do
      seconds = Sanbase.DateTimeUtils.str_to_sec(time_period)
      to_datetime = now
      from_datetime = DateTime.add(to_datetime, -seconds, :second)
      {:ok, {from_datetime, to_datetime}}
    else
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
    end
  end

  @doc """
  Validates a size parameter, ensuring it's between 1 and 30.

  ## Examples

      iex> Sanbase.MCP.Utils.validate_size(10, 1, 10)
      {:ok, 10}

      iex> Sanbase.MCP.Utils.validate_size(50, 1, 10)
      {:error, "Size must be between 1 and 10 inclusively, got: 50"}

      iex> Sanbase.MCP.Utils.validate_size("invalid", 1, 10)
      {:error, "Size must be an integer"}
  """
  @spec validate_size(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, String.t()}
  def validate_size(size, min, max) when is_integer(size) and size >= min and size <= max do
    {:ok, size}
  end

  def validate_size(size, min, max) when is_integer(size) do
    {:error, "Size must be between #{min} and #{max} inclusively, got: #{size}"}
  end

  def validate_size(_size, _min, _max) do
    {:error, "Size must be an integer"}
  end

  @doc """
  Truncates a JSON-encodable response to stay within the MCP token limit.

  The MCP specification requires tool results to be at most 25,000 tokens.
  As a conservative estimate, 1 token ~ 4 characters, so we cap at 80,000 characters.
  """
  @max_response_chars 80_000
  @max_truncation_attempts 100
  @truncation_notice "Response was truncated to stay within the 25,000 token limit. Use more specific parameters to narrow results."
  def truncate_response(data) when is_map(data) do
    json = Jason.encode!(data)

    if byte_size(json) <= @max_response_chars do
      data
    else
      Map.put(data, :truncated, true)
      |> Map.put(:truncation_notice, @truncation_notice)
      |> do_truncate_map()
    end
  end

  def truncate_response(data), do: data

  defp do_truncate_map(data) do
    data =
      data
      |> shrink_to_fit(@max_response_chars, [:list, :string])
      |> shrink_to_fit(@max_response_chars, [:map])

    data =
      data
      |> sync_relationship_fields()
      |> sync_count_fields()

    data
  end

  defp shrink_to_fit(data, max_chars, candidate_types, attempts \\ 0)

  defp shrink_to_fit(data, _max_chars, _candidate_types, attempts)
       when attempts >= @max_truncation_attempts,
       do: data

  defp shrink_to_fit(data, max_chars, candidate_types, attempts) do
    if byte_size(Jason.encode!(data)) <= max_chars do
      data
    else
      case largest_truncatable_path(data, candidate_types) do
        nil ->
          data

        path ->
          updated_data =
            data
            |> truncate_at_path(path)
            |> sync_relationship_fields()
            |> sync_count_fields()

          if updated_data == data do
            data
          else
            shrink_to_fit(updated_data, max_chars, candidate_types, attempts + 1)
          end
      end
    end
  end

  defp largest_truncatable_path(data, candidate_types) do
    protected_paths = protected_paths(data)

    data
    |> collect_truncatable_paths([], candidate_types, protected_paths)
    |> Enum.max_by(fn {path, size} -> {size, length(path)} end, fn -> nil end)
    |> case do
      {path, _size} -> path
      nil -> nil
    end
  end

  defp collect_truncatable_paths(data, path, candidate_types, protected_paths) do
    current_path =
      if path != [] and path_truncatable?(data, path, candidate_types, protected_paths) do
        [{path, serialized_size(data)}]
      else
        []
      end

    nested_paths =
      cond do
        is_map(data) ->
          Enum.flat_map(data, fn {key, value} ->
            collect_truncatable_paths(value, path ++ [key], candidate_types, protected_paths)
          end)

        is_list(data) ->
          Enum.with_index(data)
          |> Enum.flat_map(fn {value, index} ->
            collect_truncatable_paths(value, path ++ [index], candidate_types, protected_paths)
          end)

        true ->
          []
      end

    current_path ++ nested_paths
  end

  defp path_truncatable?(data, path, candidate_types, protected_paths) do
    path not in protected_paths and truncatable_value?(data, candidate_types)
  end

  defp truncatable_value?(data, candidate_types) do
    Enum.any?(candidate_types, fn
      :list -> is_list(data) and length(data) > 1
      :map -> is_map(data) and map_size(data) > 1
      :string -> is_binary(data) and byte_size(data) > 200
    end)
  end

  defp truncate_at_path(data, [key]) when is_map(data) do
    Map.update!(data, key, &truncate_value/1)
  end

  defp truncate_at_path(data, [index]) when is_list(data) do
    List.update_at(data, index, &truncate_value/1)
  end

  defp truncate_at_path(data, [key | rest]) when is_map(data) do
    Map.update!(data, key, &truncate_at_path(&1, rest))
  end

  defp truncate_at_path(data, [index | rest]) when is_list(data) do
    List.update_at(data, index, &truncate_at_path(&1, rest))
  end

  defp truncate_value(data) when is_list(data) do
    target_len = max(div(length(data), 2), 1)
    Enum.take(data, target_len)
  end

  defp truncate_value(data) when is_map(data) do
    target_size = max(div(map_size(data), 2), 1)

    data
    |> Enum.sort_by(fn {key, value} -> {serialized_size(value), inspect(key)} end)
    |> Enum.take(target_size)
    |> Map.new()
  end

  defp truncate_value(data) when is_binary(data) do
    String.slice(data, 0, 200) <> "... [truncated]"
  end

  defp truncate_value(data), do: data

  defp protected_paths(data) do
    case {map_key(data, :slugs), map_key(data, :data)} do
      {slugs_key, data_key} when not is_nil(slugs_key) and not is_nil(data_key) ->
        if is_list(Map.get(data, slugs_key)) and is_map(Map.get(data, data_key)) do
          [[slugs_key]]
        else
          []
        end

      _ ->
        []
    end
  end

  defp sync_relationship_fields(data) do
    data
    |> sync_slugs_with_data()
    |> sync_included_types_with_trends()
  end

  defp sync_slugs_with_data(data) do
    case {map_key(data, :slugs), map_key(data, :data)} do
      {slugs_key, data_key} when not is_nil(slugs_key) and not is_nil(data_key) ->
        slugs = Map.get(data, slugs_key)
        data_map = Map.get(data, data_key)

        if is_list(slugs) and is_map(data_map) do
          synced_slugs = Enum.filter(slugs, &Map.has_key?(data_map, &1))
          Map.put(data, slugs_key, synced_slugs)
        else
          data
        end

      _ ->
        data
    end
  end

  defp sync_included_types_with_trends(data) do
    with metadata_key when not is_nil(metadata_key) <- map_key(data, :metadata),
         trends_key when not is_nil(trends_key) <- map_key(data, :trends),
         metadata when is_map(metadata) <- Map.get(data, metadata_key),
         included_types_key when not is_nil(included_types_key) <-
           map_key(metadata, :included_data_types),
         trends when is_map(trends) <- Map.get(data, trends_key),
         included_types when is_list(included_types) <- Map.get(metadata, included_types_key) do
      available_types =
        []
        |> maybe_add_type(trends, :trending_stories, "stories")
        |> maybe_add_type(trends, :trending_words, "words")

      synced_types = Enum.filter(included_types, &(&1 in available_types))

      Map.put(data, metadata_key, Map.put(metadata, included_types_key, synced_types))
    else
      _ -> data
    end
  end

  defp maybe_add_type(types, trends, trend_key, type_name) do
    if is_nil(map_key(trends, trend_key)) do
      types
    else
      types ++ [type_name]
    end
  end

  defp serialized_size(data) do
    Jason.encode!(data) |> byte_size()
  end

  defp map_key(map, atom_key) do
    cond do
      Map.has_key?(map, atom_key) -> atom_key
      Map.has_key?(map, Atom.to_string(atom_key)) -> Atom.to_string(atom_key)
      true -> nil
    end
  end

  defp sync_count_fields(data) do
    data
    |> sync_named_count_fields()
    |> sync_total_count()
  end

  defp sync_named_count_fields(data) do
    Enum.reduce(data, data, fn
      {key, value}, acc when is_list(value) ->
        count_key = count_key_for_list_key(key)

        if Map.has_key?(acc, count_key) do
          Map.put(acc, count_key, length(value))
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp sync_total_count(data) do
    case total_count_key(data) do
      nil ->
        data

      count_key ->
        case primary_list_key(data) do
          nil -> data
          list_key -> Map.put(data, count_key, data |> Map.fetch!(list_key) |> length())
        end
    end
  end

  defp total_count_key(data) do
    cond do
      Map.has_key?(data, :total_count) -> :total_count
      Map.has_key?(data, "total_count") -> "total_count"
      true -> nil
    end
  end

  defp primary_list_key(data) do
    case Enum.filter(data, fn {_key, value} -> is_list(value) end) do
      [] ->
        nil

      lists ->
        {key, _value} =
          Enum.max_by(lists, fn {_key, value} -> byte_size(Jason.encode!(value)) end)

        key
    end
  end

  defp count_key_for_list_key(key) when is_atom(key), do: :"#{key}_count"
  defp count_key_for_list_key(key) when is_binary(key), do: "#{key}_count"
end
