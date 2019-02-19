defmodule Sanbase.Signals.History.PricesHistory do
  import Sanbase.Signals.Utils
  import Sanbase.Signals.History.Utils

  alias Sanbase.Signals.Trigger.{
    PriceAbsoluteChangeSettings,
    PricePercentChangeSettings
  }

  alias Sanbase.Model.Project
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Prices.Store, as: PricesStore
  require Logger

  @historical_days_from 90
  @historical_days_interval "1h"

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          price: float(),
          triggered?: boolean()
        }

  def get_prices(settings) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(settings.target),
         {from, to, interval} <- get_timeseries_params(settings),
         {:ok, price_list} when is_list(price_list) and price_list != [] <-
           PricesStore.fetch_prices_with_resolution(measurement, from, to, interval) do
      prices = Enum.map(price_list, fn [_, price | _rest] -> price end)
      datetimes = Enum.map(price_list, fn [dt, _ | _rest] -> dt end)
      {:ok, prices, datetimes}
    else
      error -> {:error, error}
    end
  end

  defp get_timeseries_params(settings) do
    now = Timex.now()
    interval = @historical_days_interval
    from = Timex.shift(now, days: -@historical_days_from)
    to = now

    {from, to, interval}
  end

  defimpl Sanbase.Signals.History, for: PriceAbsoluteChangeSettings do
    alias Sanbase.Signals.History.PricesHistory

    @spec historical_trigger_points(%PriceAbsoluteChangeSettings{}, String.t()) ::
            {:ok, list(PricesHistory.historical_trigger_points_type())} | {:error, String.t()}
    def historical_trigger_points(
          %PriceAbsoluteChangeSettings{target: target} = settings,
          cooldown
        ) do
      {:ok, prices, datetimes} = PricesHistory.get_prices(settings)
      above = Map.get(settings, :above)
      below = Map.get(settings, :below)
      cooldown_in_hours = Sanbase.DateTimeUtils.compound_duration_to_hours(cooldown)

      {absolute_price_calculations, _} =
        prices
        |> Enum.reduce({[], 0}, fn
          price, {accumulated_calculations, 0} ->
            if (is_number(above) and price >= above) or (is_number(below) and price <= below) do
              {[true | accumulated_calculations], cooldown_in_hours}
            else
              {[false | accumulated_calculations], 0}
            end

          price, {accumulated_calculations, cooldown_left} ->
            {[false | accumulated_calculations], cooldown_left - 1}
        end)

      absolute_price_calculations = absolute_price_calculations |> Enum.reverse()

      points =
        Enum.zip([datetimes, prices, absolute_price_calculations])
        |> Enum.map(fn {dt, price, triggered?} ->
          %{
            datetime: dt,
            price: price,
            triggered?: triggered?
          }
        end)

      {:ok, points}
    end
  end

  defimpl Sanbase.Signals.History, for: PricePercentChangeSettings do
    alias Sanbase.Signals.History.PricesHistory

    @spec historical_trigger_points(%PricePercentChangeSettings{}, String.t()) ::
            {:ok, list(PricesHistory.historical_trigger_points_type())} | {:error, String.t()}

    def historical_trigger_points(
          %PricePercentChangeSettings{target: target} = settings,
          cooldown
        ) do
      {:ok, prices, datetimes} = PricesHistory.get_prices(settings)

      time_window_in_hours =
        max(2, Sanbase.DateTimeUtils.compound_duration_to_hours(settings.time_window))

      cooldown_in_hours = Sanbase.DateTimeUtils.compound_duration_to_hours(cooldown)

      {percent_change_calculations, _} =
        prices
        |> Enum.chunk_every(time_window_in_hours, 1, :discard)
        |> Enum.map(fn chunk -> {List.first(chunk), List.last(chunk)} end)
        |> Enum.map(fn {a, b} -> percent_change(a, b) end)
        |> Enum.reduce({[], 0}, fn
          percent_change, {accumulated_calculations, 0} ->
            if percent_change > settings.percent_threshold do
              {[{percent_change, true} | accumulated_calculations], cooldown_in_hours}
            else
              {[{percent_change, false} | accumulated_calculations], 0}
            end

          percent_change, {accumulated_calculations, cooldown_left} ->
            {[{percent_change, false} | accumulated_calculations], cooldown_left - 1}
        end)

      percent_change_calculations = percent_change_calculations |> Enum.reverse()
      empty_calculations = for _ <- 1..(time_window_in_hours - 1), do: {0.0, false}

      points =
        Enum.zip([datetimes, prices, empty_calculations ++ percent_change_calculations])
        |> Enum.map(fn {dt, price, {percent_change, triggered?}} ->
          %{
            datetime: dt,
            price: price,
            triggered?: triggered?,
            percent_change: percent_change
          }
        end)

      {:ok, points}
    end
  end
end
