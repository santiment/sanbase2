defmodule Sanbase.Alert.List do
  alias Sanbase.Alert.Trigger

  def get() do
    [
      Trigger.DailyMetricTriggerSettings,
      Trigger.EthWalletTriggerSettings,
      Trigger.MetricTriggerSettings,
      Trigger.RawSignalTriggerSettings,
      Trigger.ScreenerTriggerSettings,
      Trigger.SignalTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.WalletAssetsHeldTriggerSettings,
      Trigger.WalletTriggerSettings,
      Trigger.WalletUsdValuationTriggerSettings
    ]
  end
end
