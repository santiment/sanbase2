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
    def historical_trigger_points(%DailyActiveAddressesSettings{target: target} = settings)
        when is_binary(target) do
      settings
      |> get_daily_active_addresses()
      |> case do
        {:ok, daa_result} when is_list(daa_result) and daa_result != [] ->
          time_window_in_days = time_window_in_days(settings.time_window)

          first_possible_trigger_date =
            first_possible_trigger_date(daa_result, time_window_in_days + 1)

          result =
            for %{datetime: datetime, active_addresses: active_addresses} <- daa_result do
              triggered? =
                point_triggered?(
                  settings,
                  {datetime, active_addresses},
                  daa_result,
                  first_possible_trigger_date,
                  time_window_in_days
                )

              %{
                datetime: datetime,
                active_addresses: active_addresses,
                triggered?: triggered?
              }
            end

          {:ok, result}

        _ ->
          {:error, "No data available to calculate historical trigger points"}
      end
    end

    def historical_trigger_points(_), do: {:error, "Not implemented"}

    defp point_triggered?(
           settings,
           {datetime, active_addresses},
           daa_result,
           first_possible_trigger_date,
           time_window_in_days
         ) do
      case DateTime.compare(datetime, first_possible_trigger_date) do
        cmp when cmp in [:gt, :eq] ->
          avg_time_window =
            filter_points_in_interval(
              daa_result,
              Timex.shift(datetime, days: -time_window_in_days),
              Timex.shift(datetime, days: -1)
            )
            |> calc_average()

          percent_change(avg_time_window, active_addresses) >= settings.percent_threshold

        _ ->
          false
      end
    end

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

    defp first_possible_trigger_date(daa_result, days_shift) do
      daa_result
      |> List.first()
      |> Map.get(:datetime)
      |> Timex.shift(days: days_shift)
    end

    def time_window_in_days(time_window) do
      case Sanbase.DateTimeUtils.compound_duration_to_days(time_window) do
        0 ->
          @minimal_time_window_in_days

        days ->
          days
      end
    end

    defp filter_points_in_interval(points, from, to) do
      points
      |> Enum.filter(fn %{datetime: dt} ->
        DateTime.to_unix(dt) >= DateTime.to_unix(from) &&
          DateTime.to_unix(dt) <= DateTime.to_unix(to)
      end)
    end

    defp calc_average(points) when length(points) == 0, do: 0

    defp calc_average(points) do
      sum = Enum.reduce(points, 0, fn %{active_addresses: daa}, acc -> acc + daa end)

      Sanbase.Utils.Math.to_integer(sum / length(points))
    end
  end
end
