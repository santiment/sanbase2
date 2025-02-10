defmodule Sanbase.Alert.Validation do
  @moduledoc false
  alias __MODULE__.NotificationChannel
  alias __MODULE__.Operation
  alias __MODULE__.Slug
  alias __MODULE__.Target

  defdelegate valid_notification_channels(), to: NotificationChannel
  defdelegate valid_notification_channel?(channel), to: NotificationChannel

  defdelegate valid_target?(target), to: Target
  defdelegate valid_crypto_address?(target), to: Target
  defdelegate valid_combine_balances_flag?(target), to: Target
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
