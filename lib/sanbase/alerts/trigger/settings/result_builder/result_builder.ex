defmodule Sanbase.Alert.ResultBuilder do
  @moduledoc """
  Help determine if an alert should be triggered
  """

  import Sanbase.Alert.OperationEvaluation
  alias Sanbase.Alert.ResultBuilder.Transformer

  @trigger_modules Sanbase.Alert.List.get()

  @doc ~s"""
  Provided the raw data and the settings, and returns the trigger settings with
  updated `triggered?` and `template_kv` fields. These fields are updated by computing
  whether or not the alert should be triggered.
  """
  def build(
        data,
        %trigger_module{operation: operation} = settings,
        template_kv_fun,
        opts \\ []
      )
      when trigger_module in @trigger_modules do
    template_kv =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = transformed_data, acc ->
        case operation_triggered?(transformed_data, operation) do
          true ->
            Map.put(
              acc,
              transformed_data.identifier,
              template_kv_fun.(transformed_data, settings)
            )

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: template_kv != %{},
        template_kv: template_kv
    }
  end
end
