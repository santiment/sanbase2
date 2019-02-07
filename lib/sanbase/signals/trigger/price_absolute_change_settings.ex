defmodule Sanbase.Signals.Trigger.PriceAbsoluteChangeSettings do
  @derive Jason.Encoder
  @trigger_type "price_absolute_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            above: nil,
            below: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Signals.Evaluator.Cache

  def type(), do: @trigger_type

  def get_data(settings) do
    Cache.get_or_store(
      "#{settings.trigger}_last_price",
      fn ->
        {:ok, [[_dt, _mcap, price_usd, _price_btc, _vol]]} =
          Project.by_slug(settings.trigger)
          |> Sanbase.Influxdb.Measurement.name_from()
          |> Sanbase.Prices.Store.last_record()

        price_usd
      end
    )
  end

  defimpl Sanbase.Signals.Settings, for: PriceAbsoluteChangeSettings do
    def triggered?(%PriceAbsoluteChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceAbsoluteChangeSettings{above: above, below: below} = settings) do
      case PriceAbsoluteChangeSettings.get_data(settings) do
        last_price_usd when last_price_usd >= above ->
          %PriceAbsoluteChangeSettings{
            settings
            | triggered?: true,
              payload: payload(settings, last_price_usd, "above $#{above}")
          }

        last_price_usd when last_price_usd <= below ->
          %PriceAbsoluteChangeSettings{
            settings
            | triggered?: true,
              payload: payload(settings, last_price_usd, "below $#{above}")
          }

        _ ->
          %PriceAbsoluteChangeSettings{settings | triggered?: false}
      end
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceAbsoluteChangeSettings{} = trigger) do
      data = [
        trigger.type,
        trigger.target,
        trigger.time_window,
        trigger.above,
        trigger.below
      ]

      :crypto.hash(:sha256, data)
      |> Base.encode16()
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

    defp payload(settings, last_price_usd, message) do
      project = Sanbase.Model.Project.by_slug(settings.target)

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
