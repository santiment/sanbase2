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

  defimpl Sanbase.Signals.Settings, for: PricePercentChangeSettings do
    @seconds_in_hour 3600
    @seconds_in_day 3600 * 24
    @seconds_in_week 3600 * 24 * 7

    def triggered?(%PricePercentChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PricePercentChangeSettings{} = settings) do
      percent_change = get_data(settings)

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

    def get_data(settings) do
      price_change_map =
        Cache.get_or_store(
          "price_change_map",
          &Sanbase.Model.Project.List.slug_price_change_map/0
        )

      target_data = Map.get(price_change_map, settings.target)

      time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)

      case time_window_sec do
        @seconds_in_hour ->
          target_data.percent_change_1h || 0

        @seconds_in_day ->
          target_data.percent_change_24h || 0

        @seconds_in_week ->
          target_data.percent_change_7d || 0

        _ ->
          0
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
        trigger.percent_threshold,
        trigger.absolute_threshold
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
