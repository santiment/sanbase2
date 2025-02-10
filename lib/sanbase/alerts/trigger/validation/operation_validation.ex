defmodule Sanbase.Alert.Validation.Operation do
  @moduledoc false
  import Sanbase.Validation

  alias Sanbase.Alert.Operation

  @percent_operations Operation.percent_operations()
  @absolute_value_operations Operation.absolute_value_operations()
  @absolute_change_operations Operation.absolute_change_operations()
  @absolute_operations Operation.absolute_operations()
  @channel_operations Operation.channel_operations()
  @combinator_operations Operation.combinator_operations()

  def valid_percent_change_operation?(operation) when is_map(operation) do
    case Map.keys(operation) do
      [op] when op in @percent_operations or op in @channel_operations ->
        valid_operation?(operation)

      [op] when op in @absolute_operations ->
        {:error, "#{inspect(operation)} is an absolute operation, not a percent change one."}

      [op] when op in @combinator_operations ->
        combinator_operation_valid?(operation, @percent_operations)

      _ ->
        {:error, "#{inspect(operation)} is not a valid percent change operation"}
    end
  end

  def valid_absolute_change_operation?(operation) do
    case Map.keys(operation) do
      [op] when op in @absolute_change_operations or op in @channel_operations ->
        valid_operation?(operation)

      [op] when op in @absolute_value_operations ->
        {:error, "#{inspect(operation)} is an absolute value operation, not an absolute change one."}

      [op] when op in @percent_operations ->
        {:error, "#{inspect(operation)} is a percent, not an absolute change one."}

      [op] when op in @combinator_operations ->
        combinator_operation_valid?(operation, @absolute_change_operations)

      _ ->
        {:error, "#{inspect(operation)} is not a valid absolute change operation"}
    end
  end

  def valid_absolute_value_operation?(operation) do
    case operation |> Map.keys() |> List.first() do
      op when op in @absolute_value_operations or op in @channel_operations ->
        valid_operation?(operation)

      op when op in @absolute_change_operations ->
        {:error, "#{operation} is an absolute change operation, not an absolute value one."}

      op when op in @percent_operations ->
        {:error, "#{operation} is a percent, not an absolute value one."}

      op when op in @combinator_operations ->
        combinator_operation_valid?(operation, @absolute_value_operations)

      _ ->
        {:error, "#{operation} is not a valid absolute value operation"}
    end
  end

  # Validate combinators
  def valid_operation?(%{some_of: list}) when is_list(list), do: valid_combinator_operation?(list)

  def valid_operation?(%{all_of: list}) when is_list(list), do: valid_combinator_operation?(list)

  def valid_operation?(%{none_of: list}) when is_list(list), do: valid_combinator_operation?(list)

  # Validate percent changes
  def valid_operation?(%{percent_up: percent} = map) when map_size(map) == 1 and is_valid_percent_change(percent), do: :ok

  def valid_operation?(%{percent_down: percent} = map) when map_size(map) == 1 and is_valid_percent_change(percent),
    do: :ok

  # Validate absolute values
  def valid_operation?(%{above: above} = map) when map_size(map) == 1 and is_number(above), do: :ok

  def valid_operation?(%{below: below} = map) when map_size(map) == 1 and is_number(below), do: :ok

  def valid_operation?(%{above_or_equal: above_or_equal} = map) when map_size(map) == 1 and is_number(above_or_equal),
    do: :ok

  def valid_operation?(%{below_or_equal: below_or_equal} = map) when map_size(map) == 1 and is_number(below_or_equal),
    do: :ok

  # Validate channels
  def valid_operation?(%{inside_channel: [min, max]}), do: valid_channel_operation?(:inside_channel, [min, max])

  def valid_operation?(%{outside_channel: [min, max]}), do: valid_channel_operation?(:outside_channel, [min, max])

  # Validate absolute value changes
  def valid_operation?(%{amount_up: value} = map) when map_size(map) == 1 and is_number(value), do: :ok

  def valid_operation?(%{amount_down: value} = map) when map_size(map) == 1 and is_number(value), do: :ok

  # Validate screener alert
  def valid_operation?(%{selector: %{watchlist_id: id}}) when is_integer(id) and id > 0, do: :ok

  def valid_operation?(%{selector: _} = selector) do
    if Sanbase.Project.ListSelector.valid_selector?(selector) do
      :ok
    else
      {:error, "The provided selector is not valid."}
    end
  end

  # All else is invalid operation
  def valid_operation?(op), do: {:error, "#{inspect(op)} is not a valid operation"}

  # Validate trending words operations
  def valid_trending_words_operation?(%{trending_word: true}), do: :ok
  def valid_trending_words_operation?(%{trending_project: true}), do: :ok

  def valid_trending_words_operation?(%{send_at_predefined_time: true, trigger_time: time_str}) do
    valid_iso8601_time_string?(time_str)
  end

  # Private functions
  defp all_operations_have_same_type?(list, operation_type) do
    Enum.all?(list, fn elem ->
      type = elem |> Map.keys() |> List.first()
      type in operation_type
    end)
  end

  defp valid_channel_operation?(op, [min, max])
       when op in [:inside_channel, :outside_channel] and is_valid_min_max(min, max),
       do: :ok

  defp valid_channel_operation?(op, [min, max]) do
    {:error, "#{inspect(op)} with arguments [#{min}, #{max}] is not a valid channel operation"}
  end

  defp all_operations_have_same_type?(list) do
    list
    |> Enum.map(&Operation.type/1)
    |> Enum.uniq()
    |> case do
      [_] -> true
      _ -> false
    end
  end

  defp combinator_operation_valid?(operation, type) do
    list = operation |> Map.values() |> List.first()

    with true <- all_operations_valid?(list),
         true <- all_operations_have_same_type?(list, type) do
      :ok
    else
      {:error, message} -> {:error, message}
      false -> {:error, "Not all operations are from the same type"}
    end
  end

  defp all_operations_valid?(list) do
    case Enum.find(list, fn op -> valid_operation?(op) != :ok end) do
      nil ->
        true

      not_valid_op ->
        {:error, "The list of operation contains not valid operation: #{inspect(not_valid_op)}"}
    end
  end

  defp valid_combinator_operation?(list) do
    with true <- all_operations_valid?(list),
         true <- all_operations_have_same_type?(list) do
      :ok
    else
      {:error, message} -> {:error, message}
      false -> {:error, "Not all operations are from the same type"}
    end
  end
end
