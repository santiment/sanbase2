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

  @max_data_points 90
  @points_for_average 2

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          price: float(),
          triggered?: boolean()
        }

  def historical_trigger_points(settings) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(settings.target),
         {from, to, interval} <- get_timeseries_params(settings),
         {:ok, prices} when is_list(prices) and prices != [] <-
           PricesStore.fetch_prices_with_resolution(measurement, from, to, interval) do
      prices =
        Enum.map(prices, fn [dt, price | _rest] ->
          %{
            datetime: dt,
            price: price,
            triggered?: false
          }
        end)

      {:ok, sma} = moving_average_excluding_last(prices, 2, :price)

      {:ok, merge_chunks_by_datetime(prices, sma)}
    else
      error ->
        Logger.error("Can't calculate historical trigger points: #{inspect(error)}")
        {:error, "No data available to calculate historical trigger points"}
    end
  end

  defp get_timeseries_params(settings) do
    now = Timex.now()
    time_window = Map.get(settings, :time_window, "1h")
    time_window_in_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(time_window)
    interval = "#{time_window_in_sec}s"
    from = Timex.shift(now, seconds: -(time_window_in_sec * @max_data_points))
    to = now

    {from, to, interval}
  end

  defimpl Sanbase.Signals.History, for: PriceAbsoluteChangeSettings do
    alias Sanbase.Signals.History.PricesHistory

    @spec historical_trigger_points(%PriceAbsoluteChangeSettings{}) ::
            {:ok, list(PricesHistory.historical_trigger_points_type())} | {:error, String.t()}
    def historical_trigger_points(%PriceAbsoluteChangeSettings{target: target} = settings) do
      settings
      |> PricesHistory.historical_trigger_points()
      |> case do
        {:ok, prices} ->
          prices =
            prices
            |> Enum.map(fn point ->
              if Map.get(point, :average) do
                triggered? =
                  (is_float(settings.above) and point.price >= settings.above) or
                    (is_float(settings.below) and point.price <= settings.below)

                Map.put(point, :triggered?, triggered?)
              else
                Map.put(point, :triggered?, false)
              end
            end)

          {:ok, prices}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defimpl Sanbase.Signals.History, for: PricePercentChangeSettings do
    alias Sanbase.Signals.History.PricesHistory

    @spec historical_trigger_points(%PricePercentChangeSettings{}) ::
            {:ok, list(PricesHistory.historical_trigger_points_type())} | {:error, String.t()}
    def historical_trigger_points(%PricePercentChangeSettings{target: target} = settings) do
      settings
      |> PricesHistory.historical_trigger_points()
      |> case do
        {:ok, prices} ->
          prices =
            prices
            |> Enum.map(fn point ->
              if Map.get(point, :average) do
                triggered? =
                  percent_change(point.average, point.price) >= settings.percent_threshold

                Map.put(point, :triggered?, triggered?)
              else
                Map.put(point, :triggered?, false)
              end
            end)

          {:ok, prices}

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
