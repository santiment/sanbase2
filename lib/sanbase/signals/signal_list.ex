defmodule Sanbase.Signal.List do
  alias Sanbase.Signal.Trigger

  def get() do
    [
      Trigger.DailyActiveAddressesSettings,
      Trigger.PricePercentChangeSettings,
      Trigger.PriceAbsoluteChangeSettings,
      Trigger.PriceVolumeDifferenceTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.EthWalletTriggerSettings,
      Trigger.MetricTriggerSettings
    ]
  end
end
