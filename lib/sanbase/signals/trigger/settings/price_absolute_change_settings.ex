defmodule Sanbase.Signals.Trigger.PriceAbsoluteChangeSettings do
  @moduledoc ~s"""
  PriceAbsoluteChangeSettings configures the settings for a signal that is fired
  when the price of `target` goes higher than `above` or lower than `below`
  """

  use Vex.Struct

  import Sanbase.Signals.{Utils, Validation, OperationEvaluation}

  alias __MODULE__
  alias Sanbase.Signals.Type

  alias Sanbase.Model.Project
  alias Sanbase.Signals.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "price_absolute_change"
  @enforce_keys [:type, :target, :channel]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target: %{list: []},
            channel: nil,
            operation: %{},
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
  validates(:operation, &valid_absolute_value_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          filtered_target: Type.filtered_target(),
          channel: Type.channel(),
          operation: Type.operation(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list}}) when is_list(target_list) do
    target_list
    |> Enum.map(fn slug ->
      {slug, get_data_by_slug(slug)}
    end)
  end

  defp get_data_by_slug(slug) when is_binary(slug) do
    Cache.get_or_store(
      "#{slug}_last_price",
      fn ->
        Project.by_slug(slug)
        |> Sanbase.Influxdb.Measurement.name_from()
        |> Sanbase.Prices.Store.last_record()
        |> case do
          {:ok, [[_dt, _mcap, _price_btc, price_usd, _vol]]} -> {:ok, price_usd}
          error -> {:error, error}
        end
      end
    )
  end

  defimpl Sanbase.Signals.Settings, for: PriceAbsoluteChangeSettings do
    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceAbsoluteChangeSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.operation
      ])
    end

    @spec triggered?(Sanbase.Signals.Trigger.PriceAbsoluteChangeSettings.t()) :: boolean()
    def triggered?(%PriceAbsoluteChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceAbsoluteChangeSettings{} = settings, _trigger) do
      case PriceAbsoluteChangeSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PriceAbsoluteChangeSettings{settings | triggered?: false}
      end
    end

    defp build_result(list, %PriceAbsoluteChangeSettings{operation: operation} = settings) do
      payload =
        Enum.reduce(list, %{}, fn {slug, {:ok, price}}, acc ->
          if operation_triggered?(price, operation) do
            Map.put(acc, slug, payload(slug, price, operation_text(operation)))
          else
            acc
          end
        end)

      %PriceAbsoluteChangeSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    defp payload(slug, last_price_usd, message) do
      project = Project.by_slug(slug)

      """
      **#{project.name}**'s price has reached #{message} and is now $#{
        round_price(last_price_usd)
      }
      More information for the project you can find here: #{Project.sanbase_link(project)}
      ![Price chart over the past 90 days](#{chart_url(project, :volume)})
      """
    end

    defp operation_text(%{above: above}), do: "above $#{above}"
    defp operation_text(%{below: below}), do: "below $#{below}"

    defp operation_text(%{inside_channel: inside_channel}) do
      [lower, upper] = inside_channel
      "between $#{lower} and $#{upper}"
    end

    defp operation_text(%{outside_channel: outside_channel}) do
      [lower, upper] = outside_channel
      "below $#{lower} or above >= $#{upper}"
    end
  end
end
