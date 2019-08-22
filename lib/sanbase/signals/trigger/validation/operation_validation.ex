defmodule Sanbase.Signal.Validation.Operation do
  import Sanbase.Validation

  alias Sanbase.Signal.Operation

  def valid_operation?(op) do
    has_valid_operation? = [
      valid_percent_change_operation?(op),
      valid_absolute_value_operation?(op)
    ]

    if Enum.member?(has_valid_operation?, :ok) do
      :ok
    else
      {:error, "#{inspect(op)} is not valid absolute change or percent change operation."}
    end
  end

  def valid_percent_change_operation?(%{some_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_percent_change_operation?(%{all_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_absolute_value_operation?(%{some_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_absolute_value_operation?(%{all_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_absolute_change_operation?(%{some_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_absolute_change_operation?(%{all_of: list}) when is_list(list) do
    all_operations_valid?(list)
  end

  def valid_percent_change_operation?(%{percent_up: percent})
      when is_valid_percent_change(percent) do
    :ok
  end

  def valid_percent_change_operation?(%{percent_down: percent})
      when is_valid_percent_change(percent) do
    :ok
  end

  def valid_percent_change_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid percent change operation"}

  def valid_absolute_value_operation?(%{above: above}) when is_valid_price(above), do: :ok
  def valid_absolute_value_operation?(%{below: below}) when is_valid_price(below), do: :ok

  def valid_absolute_value_operation?(%{inside_channel: [min, max]} = operation),
    do: do_valid_absolute_value_operation?(operation, [min, max])

  def valid_absolute_value_operation?(%{outside_channel: [min, max]} = operation),
    do: do_valid_absolute_value_operation?(operation, [min, max])

  def valid_absolute_value_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid absolute value operation"}

  def valid_absolute_change_operation?(%{amount_up: value}) when is_number(value), do: :ok
  def valid_absolute_change_operation?(%{amount_down: value}) when is_number(value), do: :ok
  def valid_absolute_change_operation?(%{amount: value}) when is_number(value), do: :ok

  def valid_absolute_change_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid absolute change operation"}

  # private functions
  defp do_valid_absolute_value_operation?(_, [min, max]) when is_valid_min_max_price(min, max),
    do: :ok

  defp do_valid_absolute_value_operation?(operation, _),
    do: {:error, "#{inspect(operation)} is not a valid absolute value operation"}

  defp all_operations_have_same_type?(list) do
    Enum.map(list, &Operation.type/1)
    |> Enum.uniq()
    |> case do
      [_] -> true
      _ -> false
    end
  end

  defp all_operations_valid?(list) do
    with true <- all_operations_have_same_type?(list),
         true <- Enum.all?(list, fn op -> valid_operation?(op) == :ok end) do
      :ok
    else
      false -> {:error, "Some of the operations are not valid"}
    end
  end
end
