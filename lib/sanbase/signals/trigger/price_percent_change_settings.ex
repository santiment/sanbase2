defmodule Sanbase.Signals.Trigger.PricePercentChangeSettings do
  @derive Jason.Encoder
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Signals.Evaluator.Cache

  def type(), do: @trigger_type

  def get_data(settings) do
    time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)
    project = Project.by_slug(settings.trigger)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    Cache.get_or_store(
      cache_key_datetimes(project, from, to),
      fn ->
        {:ok, [[_dt, first_usd_price, last_usd_price]]} =
          Sanbase.Prices.Store.first_last_price(
            Sanbase.Influxdb.Measurement.name_from(project),
            from,
            to
          )

        if first_usd_price >= 0.0000001 do
          (last_usd_price - first_usd_price) / first_usd_price * 100
        else
          0
        end
      end
    )
  end

  defp cache_key_datetimes(project, from, to) do
    # we have prices each 5 minutes
    from_rounded = div(DateTime.to_unix(from, :second), 300) * 300
    to_rounded = div(DateTime.to_unix(to, :second), 300) * 300

    "first_last_#{project.id}_#{from_rounded}_#{to_rounded}"
  end

  defimpl Sanbase.Signals.Settings, for: PricePercentChangeSettings do
    def triggered?(%PricePercentChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PricePercentChangeSettings{} = settings) do
      percent_change = PricePercentChangeSettings.get_data(settings)

      case percent_change >= settings.percent_threshold do
        true ->
          %PricePercentChangeSettings{
            settings
            | triggered?: true,
              payload: payload(settings, percent_change)
          }

        _ ->
          %PricePercentChangeSettings{settings | triggered?: false}
      end
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PricePercentChangeSettings{} = trigger) do
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

    defp payload(settings, percent_change) do
      project = Sanbase.Model.Project.by_slug(settings.target)

      """
      The price of **#{project.name}** has changed by **#{percent_change}%** for the last #{
        Sanbase.DateTimeUtils.compound_duration_to_text(settings.time_window)
      }.
      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      ![Price chart over the past 90 days](#{chart_url(project)})
      """
    end
  end
end
