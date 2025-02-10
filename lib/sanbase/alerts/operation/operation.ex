defmodule Sanbase.Alert.Operation do
  @moduledoc ~s"""
  Module providing definitions of different operations and checking operation type.
  """

  @percent_operations [:percent_up, :percent_down]
  @absolute_value_operations [:above, :below, :above_or_equal, :below_or_equal]
  @absolute_change_operations [:amount_up, :amount_down]
  @absolute_operations @absolute_change_operations ++ @absolute_value_operations
  @channel_operations [:inside_channel, :outside_channel]
  @combinator_operations [:some_of, :all_of, :none_of]

  def percent_operations, do: @percent_operations
  def absolute_value_operations, do: @absolute_value_operations
  def absolute_change_operations, do: @absolute_change_operations
  def absolute_operations, do: @absolute_operations
  def channel_operations, do: @channel_operations
  def combinator_operations, do: @combinator_operations

  @spec type(map()) :: :percent | :absolute | :channel | :combinator
  def type(operation_map) when is_map(operation_map) and map_size(operation_map) == 1 do
    operation = operation_map |> Map.keys() |> List.first()

    case operation do
      op when op in @percent_operations -> :percent
      op when op in @absolute_operations -> :absolute
      op when op in @channel_operations -> :channel
      op when op in @combinator_operations -> :combinator
    end
  end

  @spec type_extended(map()) ::
          :percent | :absolute_value | :absolute_change | :channel | :combinator
  def type_extended(operation_map) when is_map(operation_map) and map_size(operation_map) == 1 do
    operation = operation_map |> Map.keys() |> List.first()

    case operation do
      op when op in @percent_operations -> :percent
      op when op in @absolute_value_operations -> :absolute_value
      op when op in @absolute_change_operations -> :absolute_change
      op when op in @channel_operations -> :channel
      op when op in @combinator_operations -> :combinator
    end
  end
end
