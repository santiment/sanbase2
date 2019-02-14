defmodule Sanbase.Signals.History.DailyActiveAddressesHistory do
  import Sanbase.Signals.Utils

  alias Sanbase.Signals.Trigger.DailyActiveAddressesSettings
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}

  defimpl Sanbase.Signals.History, for: DailyActiveAddressesSettings do
    @historical_days_from 90
    @historical_days_to 1
    @historical_days_interval "1d"
    @minimal_time_window_in_days 2

    @type historical_trigger_points_type :: %{
            datetime: %DateTime{},
            active_addresses: non_neg_integer(),
            triggered?: boolean()
          }

    @spec historical_trigger_points(%DailyActiveAddressesSettings{}) ::
            {:ok, list(historical_trigger_points_type)} | {:error, String.t()}
    def historical_trigger_points(%DailyActiveAddressesSettings{target: target} = settings) do
      settings
      |> get_daily_active_addresses()
      |> case do
        {:ok, daa_result} when is_list(daa_result) and daa_result != [] ->
          daa_result = Enum.map(daa_result, fn point -> Map.put(point, :triggered?, false) end)
          time_window_in_days = time_window_in_days(settings.time_window)
          {:ok, sma} = sma(daa_result, time_window_in_days + 1)

          sma =
            sma
            |> Enum.map(fn point ->
              triggered? =
                percent_change(point.average_daa, point.active_addresses) >=
                  settings.percent_threshold

              Map.put(point, :triggered?, triggered?)
            end)

          {:ok, merge_daa_chunks_by_datetime(daa_result, sma)}

        _ ->
          {:error, "No data available to calculate historical trigger points"}
      end
    end

    def historical_trigger_points(_), do: {:error, "Not implemented"}

    defp get_daily_active_addresses(settings) do
      {:ok, contract, _token_decimals} = Project.contract_info_by_slug(settings.target)

      from = Timex.shift(Timex.now(), days: -@historical_days_from)
      to = Timex.shift(Timex.now(), days: -@historical_days_to)
      interval = @historical_days_interval

      if contract == "ETH" do
        EthDailyActiveAddresses.average_active_addresses(from, to, interval)
      else
        Erc20DailyActiveAddresses.average_active_addresses(contract, from, to, interval)
      end
    end

    defp sma(list, period) when is_list(list) and is_integer(period) and period > 0 do
      result =
        list
        |> Enum.chunk_every(period, 1, :discard)
        |> Enum.map(fn elems ->
          active_addresses = elems |> List.last() |> Map.get(:active_addresses)
          {datetime, average_daa} = average(elems)

          %{
            datetime: datetime,
            active_addresses: active_addresses,
            average_daa: average_daa
          }
        end)

      {:ok, result}
    end

    defp average([]), do: 0

    defp average(l) when is_list(l) do
      values = Enum.map(l, fn %{active_addresses: daa} -> daa end) |> Enum.drop(-1)
      %{datetime: datetime} = List.last(l)
      average_daa = Sanbase.Utils.Math.to_integer(Enum.sum(values) / length(values))

      {datetime, average_daa}
    end

    defp merge_daa_chunks_by_datetime(daa_result, sma) do
      daa_result
      |> Enum.map(fn point ->
        Enum.find(sma, point, fn sma_point ->
          DateTime.compare(sma_point.datetime, point.datetime) == :eq
        end)
      end)
    end

    defp time_window_in_days(time_window) do
      case Sanbase.DateTimeUtils.compound_duration_to_days(time_window) do
        0 ->
          @minimal_time_window_in_days

        days ->
          days
      end
    end
  end
end
