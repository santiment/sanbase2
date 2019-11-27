defmodule Sanbase.Signal.List do
  alias Sanbase.Signal.Trigger

  def get() do
    [
      Trigger.DailyActiveAddressesSettings,
      Trigger.PricePercentChangeSettings,
      Trigger.PriceSettings,
      Trigger.PriceAbsoluteChangeSettings,
      Trigger.PriceVolumeDifferenceTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.EthWalletTriggerSettings,
      Trigger.WalletTriggerSettings,
      Trigger.MetricTriggerSettings
    ]
  end
end
