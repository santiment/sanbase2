defmodule Sanbase.Signal.History.DailyActiveAddressesHistory do
  @moduledoc """
  Implementation of historical_trigger_points for daily active addresses.
  Currently it is bucketed in `1 day` intervals and goes 90 days back.
  """

  alias __MODULE__
  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          price: float(),
          triggered?: boolean(),
          percent_change: float()
        }

  defimpl Sanbase.Signal.History, for: DailyActiveAddressesSettings do
    import Sanbase.DateTimeUtils, only: [str_to_days: 1]

    alias Sanbase.Signal.History.ResultBuilder
    alias Sanbase.Signal.History.DailyActiveAddressesHistory
    alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

    @historical_days_from 90
    @historical_days_interval "1d"

    @spec historical_trigger_points(%DailyActiveAddressesSettings{}, String.t()) ::
            {:ok, list(DailyActiveAddressesHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %DailyActiveAddressesSettings{target: %{slug: slug}, time_window: time_window} =
            settings,
          cooldown
        )
        when is_binary(slug) do
      case get_data(slug, time_window) do
        {:ok, data} ->
          ResultBuilder.build(data, settings, cooldown, value_key: :value)
          |> Sanbase.Utils.Transform.rename_map_keys(
            old_key: :current,
            new_key: :active_addresses
          )

        {:error, error} ->
          {:error, error}
      end
    end

    def historical_trigger_points(_, _) do
      {:error, "Historical trigger points is available only when the target is a slug"}
    end

    defp get_data(slug, time_window) when is_binary(slug) do
      to = Timex.now()
      shift = @historical_days_from + str_to_days(time_window) - 1

      Sanbase.Clickhouse.Metric.get(
        "daily_active_addresses",
        slug,
        Timex.shift(to, days: -shift),
        to,
        @historical_days_interval,
        :avg
      )
    end
  end
end
