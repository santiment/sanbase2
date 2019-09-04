defmodule Sanbase.Signal.Validation.Operation do
  import Sanbase.Validation

  alias Sanbase.Signal.Operation

  @percent_operations [:percent_up, :percent_down]
  @absolute_value_operations [:above, :below]
  @absolute_change_operations [:amount_up, :amount_down]
  @absolute_operations @absolute_change_operations ++ @absolute_value_operations

  @channel_operations [:inside_channel, :outside_channel]
  @combinator_operations [:some_of, :all_of]

  def valid_percent_change_operation?(operation) when is_map(operation) do
    case Map.keys(operation) do
      [op] when op in @percent_operations or op in @channel_operations ->
        valid_operation?(operation)

      [op] when op in @absolute_operations ->
        {:error, "#{inspect(operation)} is an absolute operation, not a percent change one."}

      [op] when op in @combinator_operations ->
        list = Map.values(operation) |> List.first()

        if check_operations?(list, @percent_operations) and all_operations_valid?(list) do
          :ok
        else
          {:error, "#{inspect(operation)} is not a valid percent change operation"}
        end

      _ ->
        {:error, "#{inspect(operation)} is not a valid percent change operation"}
    end
  end

  def valid_absolute_change_operation?(operation) do
    case Map.keys(operation) do
      [op] when op in @absolute_change_operations or op in @channel_operations ->
        valid_operation?(operation)

      [op] when op in @absolute_value_operations ->
        {:error,
         "#{inspect(operation)} is an absolute value operation, not an absolute percent change one."}

      [op] when op in @percent_operations ->
        {:error, "#{inspect(operation)} is a percent, not an absolute percent change one."}

      [op] when op in @combinator_operations ->
        list = Map.values(operation) |> List.first()

        if check_operations?(list, @absolute_change_operations) and all_operations_valid?(list) do
          :ok
        else
          {:error, "#{inspect(operation)} is not a valid absolute change operation"}
        end

      _ ->
        {:error, "#{inspect(operation)} is not a valid absolute change operation"}
    end
  end

  def valid_absolute_value_operation?(operation) do
    case Map.keys(operation) do
      [op] when op in @absolute_value_operations or op in @channel_operations ->
        valid_operation?(operation)

      [op] when op in @absolute_change_operations ->
        {:error,
         "#{inspect(operation)} is an absolute change operation, not an absolute value change one."}

      [op] when op in @percent_operations ->
        {:error, "#{inspect(operation)} is a percent, not an absolute value change one."}

      [op] when op in @combinator_operations ->
        list = Map.values(operation) |> List.first()

        if check_operations?(list, @absolute_value_operations) and all_operations_valid?(list) do
          :ok
        else
          {:error, "#{inspect(operation)} is not a valid absoltue value operation"}
        end

      _ ->
        {:error, "#{inspect(operation)} is not a valid absoltue value operatio"}
    end
  end

  def valid_operation?(%{some_of: list}) when is_list(list), do: all_operations_valid?(list)
  def valid_operation?(%{all_of: list}) when is_list(list), do: all_operations_valid?(list)
  def valid_operation?(%{percent_up: percent}) when is_valid_percent_change(percent), do: :ok
  def valid_operation?(%{percent_down: percent}) when is_valid_percent_change(percent), do: :ok
  def valid_operation?(%{above: above}) when is_valid_price(above), do: :ok
  def valid_operation?(%{below: below}) when is_valid_price(below), do: :ok

  def valid_operation?(%{inside_channel: [min, max]}),
    do: valid_channel_operation?(:inside_channel, [min, max])

  def valid_operation?(%{outside_channel: [min, max]}),
    do: valid_channel_operation?(:outside_channel, [min, max])

  def valid_operation?(%{amount_up: value}) when is_number(value), do: :ok
  def valid_operation?(%{amount_down: value}) when is_number(value), do: :ok
  def valid_operation?(op), do: {:error, "#{inspect(op)} is not a valid operation"}

  # Private functions
  defp check_operations?(list, operation_type) do
    Enum.all?(list, fn elem ->
      type = Map.keys(elem) |> List.first()
      type in operation_type
    end)
  end

  defp valid_channel_operation?(op, [min, max])
       when op in [:inside_channel, :outside_channel] and is_valid_min_max_price(min, max),
       do: :ok

  defp valid_channel_operation?(op, [min, max]) do
    {:error, "#{inspect(op)} with arguments [#{min}, #{max}] is not a valid channel operation"}
  end

  defp all_operations_have_same_type?(list) do
    Enum.map(list, &Operation.type/1)
    |> Enum.uniq()
    |> case do
      [_] -> true
      _ -> false
    end
  end

  defp all_operations_valid?(list) do
    list = List.wrap(list)

    with true <- all_operations_have_same_type?(list),
         true <- Enum.all?(list, fn op -> valid_operation?(op) == :ok end) do
      :ok
    else
      false -> {:error, "Some of the operations are not valid"}
    end
  end
end
