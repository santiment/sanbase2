defmodule Sanbase.Signal.ResultBuilder do
  @moduledoc """
  Help determine if a signal should be triggered
  """

  import Sanbase.Signal.OperationEvaluation
  alias Sanbase.Signal.ResultBuilder.Transformer

  @trigger_modules Sanbase.Signal.List.get()

  @doc ~s"""
  Provided the raw data and the settings, and returns the trigger settings with
  updated `triggered?` and `payload` fields. These fields are updated by computing
  whether or not the signal should be triggered.
  """
  def build(
        data,
        %trigger_module{operation: operation} = settings,
        payload_fun,
        opts \\ []
      )
      when trigger_module in @trigger_modules do
    payload =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = transformed_data, acc ->
        case operation_triggered?(transformed_data, operation) do
          true ->
            Map.put(
              acc,
              transformed_data.slug,
              payload_fun.(transformed_data, settings)
            )

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: payload != %{},
        payload: payload
    }
  end
end
