defmodule Sanbase.Signals.Trigger.PriceAbsoluteChangeSettings do
  @moduledoc ~s"""
  PriceAbsoluteChangeSettings configures the settings for a signal that is fired
  when the price of `target` goes higher than `above` or lower than `below`
  """

  use Vex.Struct

  import Sanbase.Signals.{Utils, Validation}

  alias __MODULE__
  alias Sanbase.Signals.Type

  alias Sanbase.Model.Project
  alias Sanbase.Signals.Evaluator.Cache

  @derive Jason.Encoder
  @trigger_type "price_absolute_change"
  @enforce_keys [:type, :target, :channel]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target_list: [],
            channel: nil,
            above: nil,
            below: nil,
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
  validates(:above, &valid_price?/1)
  validates(:below, &valid_price?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          above: number(),
          below: number(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

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

  def get_data(%__MODULE__{filtered_target_list: target_list}) when is_list(target_list) do
    target_list
    |> Enum.map(fn slug ->
      {slug, get_data_by_slug(slug)}
    end)
  end

  defimpl Sanbase.Signals.Settings, for: PriceAbsoluteChangeSettings do
    @spec triggered?(Sanbase.Signals.Trigger.PriceAbsoluteChangeSettings.t()) :: boolean()
    def triggered?(%PriceAbsoluteChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceAbsoluteChangeSettings{} = settings) do
      case PriceAbsoluteChangeSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PriceAbsoluteChangeSettings{settings | triggered?: false}
      end
    end

    defp build_result(list, %PriceAbsoluteChangeSettings{above: above, below: below} = settings) do
      payload =
        Enum.reduce(list, %{}, fn
          {slug, {:ok, price}}, acc when price >= above ->
            Map.put(acc, slug, payload(slug, price, "above $#{above}"))

          {slug, {:ok, price}}, acc when price <= below ->
            Map.put(acc, slug, payload(slug, price, "below $#{below}"))

          _, acc ->
            acc
        end)

      %PriceAbsoluteChangeSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameter like `channel` is discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceAbsoluteChangeSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.above,
        settings.below
      ])
    end

    defp chart_url(project) do
      Sanbase.Chart.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now()
      )
      |> case do
        [%{image: %{url: chart_url}}] -> chart_url
        _ -> nil
      end
    end

    defp payload(slug, last_price_usd, message) do
      project = Sanbase.Model.Project.by_slug(slug)

      """
      The price of **#{project.name}** is $#{last_price_usd} which is #{message}
      More information for the project you can find here: #{
        Sanbase.Model.Project.sanbase_link(project)
      }
      ![Price chart over the past 90 days](#{chart_url(project)})
      """
    end
  end
end
