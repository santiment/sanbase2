defmodule Sanbase.Signals.History.PriceVolumeDifferenceHistory do
  @moduledoc """
  Implementations of historical trigger points for price_volume_difference.
  The history goes 180 days back.
  """

  import Sanbase.Signals.History.Utils

  alias Sanbase.Signals.Trigger.PriceVolumeDifferenceTriggerSettings

  require Logger

  @historical_days_from 180

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          price_volume_diff: float(),
          triggered?: boolean()
        }

  defimpl Sanbase.Signals.History, for: PriceVolumeDifferenceTriggerSettings do
    alias Sanbase.Signals.History.PriceVolumeDifferenceHistory

    @spec historical_trigger_points(%PriceVolumeDifferenceTriggerSettings{}, String.t()) ::
            {:ok, list(PriceVolumeDiffHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %PriceVolumeDifferenceTriggerSettings{target: target} = settings,
          cooldown
        )
        when is_binary(target) do
      case get_price_volume_data(settings, cooldown) do
        {:ok, result} ->
          result = result |> add_triggered_marks(cooldown, settings)
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end

    defp get_price_volume_data(settings, cooldown) do
      Sanbase.TechIndicators.PriceVolumeDifference.price_volume_diff(
        Sanbase.Model.Project.by_slug(settings.target),
        "USD",
        Timex.shift(Timex.now(), days: -90),
        Timex.now(),
        settings.aggregate_interval,
        settings.window_type,
        settings.approximation_window,
        settings.comparison_window
      )
    end

    defp add_triggered_marks(result, cooldown, settings) do
      threshold = settings.threshold

      result
      |> Enum.reduce({[], DateTime.from_unix!(0)}, fn
        %{datetime: datetime, price_volume_diff: pvd} = elem, {acc, cooldown_until} ->
          # triggered if not in cooldown and the value is above the threshold
          triggered? = DateTime.compare(datetime, cooldown_until) != :lt and pvd >= threshold

          case triggered? do
            false ->
              new_elem = elem |> Map.put(:triggered?, false)
              {[new_elem | acc], cooldown_until}

            true ->
              new_elem = elem |> Map.put(:triggered?, true)

              cooldown_until =
                Timex.shift(datetime,
                  seconds: Sanbase.DateTimeUtils.compound_duration_to_seconds(cooldown)
                )

              {[new_elem | acc], cooldown_until}
          end
      end)
      |> elem(0)
      |> Enum.reverse()
    end
  end
end
