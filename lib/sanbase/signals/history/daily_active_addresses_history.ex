defmodule Sanbase.Signals.History.DailyActiveAddressesHistory do
  import Sanbase.Signals.Utils
  import Sanbase.Signals.History.Utils

  alias Sanbase.Signals.Trigger.DailyActiveAddressesSettings
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Prices.Store, as: PricesStore
  require Logger

  defimpl Sanbase.Signals.History, for: DailyActiveAddressesSettings do
    @historical_days_from 90
    @historical_days_to 1
    @historical_days_interval "1d"
    @minimal_time_window_in_days 2

    @type historical_trigger_points_type :: %{
            datetime: %DateTime{},
            active_addresses: non_neg_integer(),
            price: float(),
            triggered?: boolean()
          }

    @spec historical_trigger_points(%DailyActiveAddressesSettings{}, String.t()) ::
            {:ok, list(historical_trigger_points_type)} | {:error, String.t()}
    def historical_trigger_points(
          %DailyActiveAddressesSettings{target: target} = settings,
          cooldown
        ) do
      with {:ok, contract, _token_decimals} <- Project.contract_info_by_slug(settings.target),
           measurement when not is_nil(measurement) <-
             Measurement.name_from_slug(settings.target),
           {from, to, interval} <- get_timeseries_params(),
           {:ok, daa_result} when is_list(daa_result) and daa_result != [] <-
             get_daily_active_addresses(contract, from, to, interval),
           {:ok, prices} when is_list(prices) and prices != [] <-
             PricesStore.fetch_prices_with_resolution(
               measurement,
               Timex.shift(from, days: -1),
               to,
               interval
             ) do
        daa_result = Enum.map(daa_result, fn point -> Map.put(point, :triggered?, false) end)
        prices = Enum.map(prices, fn [dt, price | _rest] -> %{datetime: dt, price: price} end)

        daa_result =
          Enum.zip(daa_result, prices)
          |> Enum.map(fn {daa_item, price_item} -> Map.merge(daa_item, price_item) end)

        time_window_in_days = time_window_in_days(settings.time_window)

        {:ok, sma} =
          moving_average_excluding_last(daa_result, time_window_in_days + 1, :active_addresses)

        sma =
          sma
          |> Enum.map(fn point ->
            point = Map.put(point, :average, Sanbase.Utils.Math.to_integer(point.average))

            triggered? =
              percent_change(point.average, point.active_addresses) >= settings.percent_threshold

            Map.put(point, :triggered?, triggered?)
          end)

        {:ok, merge_chunks_by_datetime(daa_result, sma)}
      else
        error ->
          Logger.error("Can't calculate historical trigger points: #{inspect(error)}")
          {:error, "No data available to calculate historical trigger points"}
      end
    end

    def historical_trigger_points(_), do: {:error, "Not implemented"}

    defp get_timeseries_params() do
      from = Timex.shift(Timex.now(), days: -@historical_days_from)
      to = Timex.shift(Timex.now(), days: -@historical_days_to)
      interval = @historical_days_interval

      {from, to, interval}
    end

    defp get_daily_active_addresses(contract, from, to, interval) do
      if contract == "ETH" do
        EthDailyActiveAddresses.average_active_addresses(from, to, interval)
      else
        Erc20DailyActiveAddresses.average_active_addresses(contract, from, to, interval)
      end
    end

    defp time_window_in_days(time_window) do
      Sanbase.DateTimeUtils.compound_duration_to_days(time_window)
      |> max(@minimal_time_window_in_days)
    end
  end
end
