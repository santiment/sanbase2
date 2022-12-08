defmodule Sanbase.Alert.History.ResultBuilder do
  import Sanbase.Alert.OperationEvaluation
  import Sanbase.Alert.History.ResultBuilder.Transformer

  def build(
        data,
        %_trigger_module{} = settings,
        cooldown,
        opts \\ []
      ) do
    %{operation: operation, time_window: time_window} = settings
    cooldown_sec = Sanbase.DateTimeUtils.str_to_sec(cooldown)

    {result, _} =
      data
      |> transform(time_window, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce({[], nil}, fn
        values, {acc, last_triggered_dt} ->
          with false <- in_cooldown(last_triggered_dt, values, cooldown_sec),
               true <- operation_triggered?(values, operation) do
            {[Map.put(values, :triggered?, true) | acc], values.datetime}
          else
            _ ->
              {[Map.put(values, :triggered?, false) | acc], last_triggered_dt}
          end
      end)

    {:ok, result |> Enum.reverse()}
  end

  # Nothing has been triggered, so no cooldown
  defp in_cooldown(nil, _, _), do: false

  # If datetime is equal or later than last_triggered_dt + cooldown
  defp in_cooldown(last_triggered_dt, %{datetime: datetime}, cooldown_sec) do
    DateTime.compare(
      datetime,
      Timex.shift(last_triggered_dt, seconds: cooldown_sec)
    ) == :lt
  end
end
