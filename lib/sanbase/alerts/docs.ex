defmodule Sanbase.Alert.Docs do
  @moduledoc false
  def academy_link(metric) do
    prefix = "https://academy.santiment.net/metrics/"

    metric_page_map = %{
      "daily_active_addresses" => "daily-active-addresses",
      "age_consumed" => "age-consumed",
      "exchange_inflow" => "exchange-funds-flow",
      "volume_usd" => "price",
      "network_profit_loss" => "network-profit-loss",
      "social_volume_total" => "social-volume"
    }

    page =
      cond do
        String.starts_with?(metric, "mvrv") -> "mvrv-ratio"
        String.starts_with?(metric, "bitmex") -> "bitmex"
        true -> metric_page_map[metric] || ""
      end

    prefix <> page
  end
end
