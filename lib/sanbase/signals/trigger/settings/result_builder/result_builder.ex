defmodule Sanbase.Signal.ResultBuilder do
  import Sanbase.Signal.OperationEvaluation

  alias Sanbase.Signal.ResultBuilder.Transformer

  @trigger_modules Sanbase.Signal.List.get()

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

  def build_result_percent(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun,
        opts \\ []
      ) do
    payload =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = value, acc ->
        case operation_triggered?(value, operation) do
          true ->
            Map.put(
              acc,
              value.slug,
              payload_fun.(:percent, value.slug, settings, value)
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

  def build_result_absolute_value(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun,
        opts \\ []
      ) do
    payload =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = value, acc ->
        case operation_triggered?(value, operation) do
          true ->
            Map.put(acc, value.slug, payload_fun.(:absolute, value.slug, settings, value))

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

  def build_result_absolute_change(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun,
        opts \\ []
      ) do
    payload =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = value, acc ->
        case operation_triggered?(value, operation) do
          true ->
            Map.put(acc, value.slug, payload_fun.(:absolute, value.slug, settings, value))

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

  def build_result_combinator(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun,
        opts \\ []
      ) do
    payload =
      Transformer.transform_absolute_change(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = value, acc ->
        case operation_triggered?(value, operation) do
          true ->
            Map.put(acc, value.slug, payload_fun.(:absolute, value.slug, settings, value))

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
