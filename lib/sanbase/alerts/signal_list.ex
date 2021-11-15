defmodule Sanbase.Alert.List do
  alias Sanbase.Alert.Trigger

  def get() do
    [
      Trigger.DailyMetricTriggerSettings,
      Trigger.EthWalletTriggerSettings,
      Trigger.MetricTriggerSettings,
      Trigger.PriceVolumeDifferenceTriggerSettings,
      Trigger.ScreenerTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.WalletTriggerSettings,
      Trigger.SignalTriggerSettings,
      Trigger.RawSignalTriggerSettings
    ]
  end
end
