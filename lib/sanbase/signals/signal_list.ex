defmodule Sanbase.Signal.List do
  alias Sanbase.Signal.Trigger

  def get() do
    [
      Trigger.DailyActiveAddressesSettings,
      Trigger.EthWalletTriggerSettings,
      Trigger.MetricTriggerSettings,
      Trigger.PriceAbsoluteChangeSettings,
      Trigger.PricePercentChangeSettings,
      Trigger.PriceVolumeDifferenceTriggerSettings,
      Trigger.ScreenerTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.WalletTriggerSettings
    ]
  end
end
