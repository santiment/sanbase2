defmodule Sanbase.Alert.History.WalletTriggerHistory do
  @moduledoc """
  Implementation of historical_trigger_points for the generic wallet movement alert.
  Currently it is bucketed in `1 day` intervals and goes 90 days back.
  """

  alias Sanbase.Alert.Trigger.WalletTriggerSettings

  defimpl Sanbase.Alert.History, for: WalletTriggerSettings do
    import Sanbase.DateTimeUtils, only: [str_to_days: 1]

    alias Sanbase.Alert.History.ResultBuilder
    alias Sanbase.Project

    @historical_days_from 180
    @historical_days_interval "1d"

    def historical_trigger_points(
          %WalletTriggerSettings{} = settings,
          cooldown
        ) do
      %{target: target, selector: selector, time_window: time_window} = settings

      case get_data(selector, target, time_window) do
        {:ok, data} -> ResultBuilder.build(data, settings, cooldown, value_key: :balance)
        {:error, error} -> {:error, error}
      end
    end

    def get_data(selector, %{slug: slug}, time_window) when is_binary(slug) do
      with {:ok, eth_addresses} <- slug |> Project.by_slug() |> Project.eth_addresses(),
           do: get_historical_balance(selector, eth_addresses, time_window)
    end

    def get_data(selector, %{address: address_or_addresses}, time_window) do
      get_historical_balance(selector, address_or_addresses, time_window)
    end

    defp get_historical_balance(selector, addresses, time_window) do
      to = Timex.now()
      shift = @historical_days_from + str_to_days(time_window) - 1
      from = Timex.shift(to, days: -shift)

      Sanbase.Clickhouse.HistoricalBalance.historical_balance(
        selector,
        addresses,
        from,
        to,
        @historical_days_interval
      )
    end
  end
end
