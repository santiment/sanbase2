defmodule Sanbase.Alert.History.Utils do
  @moduledoc false
  import Sanbase.Alert.OperationEvaluation, only: [operation_triggered?: 2]
  import Sanbase.Math, only: [percent_change: 2]

  @type percent_change_calculations :: {float(), boolean()}

  @doc ~s"""
  * Takes a list of tuples: {grouped_value, current}
  * calculates the percent_change between grouped_value and current
  * then calculates a list of tuples {percent_change, condition_met} where condition_met is
  the percent_change bigger than threshold param and not in cooldown
  """
  @spec percent_change_calculations_with_cooldown(
          list({number(), number()}),
          float() | map(),
          non_neg_integer()
        ) :: list(percent_change_calculations)
  def percent_change_calculations_with_cooldown(values, operation, cooldown) do
    {percent_change_calculations, _} =
      values
      |> Enum.map(fn {grouped_value, current} ->
        percent_change(grouped_value, current)
      end)
      |> Enum.reduce({[], 0}, fn
        percent_change, {accumulated_calculations, 0} ->
          if operation_triggered?(percent_change, operation) do
            {[{percent_change, true} | accumulated_calculations], cooldown}
          else
            {[{percent_change, false} | accumulated_calculations], 0}
          end

        percent_change, {accumulated_calculations, cooldown_left} ->
          {[{percent_change, false} | accumulated_calculations], cooldown_left - 1}
      end)

    Enum.reverse(percent_change_calculations)
  end
end
