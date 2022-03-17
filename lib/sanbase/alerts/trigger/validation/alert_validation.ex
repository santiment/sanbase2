defmodule Sanbase.Alert.Validation do
  alias __MODULE__.{NotificationChannel, Target, Operation, Slug}

  defdelegate valid_notification_channels(), to: NotificationChannel
  defdelegate valid_notification_channel?(channel), to: NotificationChannel

  defdelegate valid_target?(target), to: Target
  defdelegate valid_crypto_address?(target), to: Target
  defdelegate valid_eth_wallet_target?(target), to: Target
  defdelegate valid_historical_balance_selector?(target), to: Target
  defdelegate valid_infrastructure_selector?(target), to: Target

  defdelegate valid_operation?(operation), to: Operation
  defdelegate valid_percent_change_operation?(operation), to: Operation
  defdelegate valid_absolute_change_operation?(operation), to: Operation
  defdelegate valid_absolute_value_operation?(operation), to: Operation
  defdelegate valid_trending_words_operation?(operation), to: Operation

  defdelegate valid_slug?(slug), to: Slug
end
