defmodule Sanbase.Pricing.Plan.AccessSeed do
  @moduledoc """
  Module that holds the access control structure of the subscription plans.
  """

  @standart_metrics [
    "burn_rate",
    "token_age_consumed",
    "transaction_volume",
    "average_token_age_consumed_in_days",
    "token_circulation",
    "token_velocity",
    "daily_active_addresses",
    "exchange_funds_flow",
    "github_activity",
    "dev_activity",
    "network_growth",
    "exchange_volume",
    "share_of_deposits",
    "historical_balance",
    "percent_of_token_supply_on_exchanges",
    "mining_pools_distribution",
    "gas_used",
    "top_holders_percent_of_total_supply"
  ]

  @advanced_metrics @standart_metrics ++
                      [
                        "daily_active_deposits",
                        "realized_value",
                        "mvrv_ratio",
                        "nvt_ratio"
                      ]

  @free %{
    api_calls_minute: 10,
    api_calls_month: 1000,
    historical_data_in_days: 90,
    metrics: @standart_metrics
  }

  @essential %{
    api_calls_minute: 60,
    api_calls_month: 10000,
    historical_data_in_days: 180,
    metrics: @standart_metrics
  }

  @pro %{
    api_calls_minute: 120,
    api_calls_month: 150_000,
    historical_data_in_days: 18 * 30,
    metrics: @advanced_metrics
  }

  @premium %{
    api_calls_minute: 180,
    api_calls_month: 500_000,
    metrics: @advanced_metrics
  }

  def free(), do: @free
  def essential(), do: @essential
  def pro(), do: @pro
  def premium(), do: @premium
  def standart_metrics(), do: @standart_metrics
  def advanced_metrics(), do: @advanced_metrics
  def all_restricted_metrics(), do: @advanced_metrics
end
