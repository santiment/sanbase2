defmodule Sanbase.Signal.History.ResultBuilder do
  import Sanbase.Signal.OperationEvaluation
  import Sanbase.Signal.History.ResultBuilder.Transformer

  @trigger_modules Sanbase.Signal.List.get()

  def build(
        data,
        %trigger_module{} = settings,
        cooldown,
        opts \\ []
      )
      when trigger_module in @trigger_modules do
    %{operation: operation, time_window: time_window} = settings
    cooldown = Sanbase.DateTimeUtils.str_to_days(cooldown)

    {result, _} =
      data
      |> transform(time_window, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce({[], 0}, fn
        values, {acc, 0} ->
          case operation_triggered?(values, operation) do
            true ->
              {[Map.put(values, :triggered?, true) | acc], cooldown}

            false ->
              {[Map.put(values, :triggered?, false) | acc], 0}
          end

        values, {acc, cooldown_left} ->
          {[Map.put(values, :triggered?, false) | acc], cooldown_left - 1}
      end)

    {:ok, result |> Enum.reverse()}
  end
end
