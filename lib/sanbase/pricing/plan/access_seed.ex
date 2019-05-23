defmodule Sanbase.Pricing.Plan.AccessSeed do
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
    "all_exchanges",
    "exchange_volume"
  ]

  @advanced_metrics @standart_metrics ++
                      [
                        "share_of_deposits",
                        "daily_active_deposits",
                        "historical_balance",
                        "percent_of_token_supply_on_exchanges",
                        "mining_pools_distribution",
                        "gas_used",
                        "top_holders_percent_of_total_supply",
                        "realized_value",
                        "mvrv_ratio",
                        "nvt_ratio"
                      ]

  @free %{
    api_calls_munute: 10,
    api_calls_month: 1000,
    historical_data_in_days: 90,
    metrics: @standart_metrics
  }

  @essential %{
    api_calls_munute: 60,
    api_calls_month: 10000,
    historical_data_in_days: 180,
    metrics: @standart_metrics
  }

  @pro %{
    api_calls_munute: 120,
    api_calls_month: 150_000,
    historical_data_in_days: 18 * 30,
    metrics: @advanced_metrics
  }

  @premeium %{
    api_calls_munute: 180,
    api_calls_month: 500_000,
    metrics: @pro[:metrics]
  }

  def free(), do: @free
  def essential(), do: @essential
  def pro(), do: @pro
  def premium(), do: @premium
  def all_restricted_metrics(), do: @advanced_metrics
end
