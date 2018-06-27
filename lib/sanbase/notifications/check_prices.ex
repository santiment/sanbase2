defmodule Sanbase.Notifications.CheckPrices do
  use Tesla

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Notifications.CheckPrices.ComputeMovements
  alias Sanbase.Utils.Config

  import Sanbase.DateTimeUtils, only: [minutes_ago: 1]

  require Sanbase.Utils.Config

  require Mockery.Macro
  defp http_client(), do: Mockery.Macro.mockable(Tesla)

  @cooldown_period_minutes 60
  @check_interval_minutes 60
  @price_change_threshold 5

  def exec(%Project{} = project, counter_currency) when counter_currency in ["BTC", "USD"] do
    if not ComputeMovements.recent_notification?(
         project,
         minutes_ago(@cooldown_period_minutes),
         counter_currency
       ) do
      ComputeMovements.build_notification(
        project,
        counter_currency,
        fetch_price_points(project),
        @price_change_threshold
      )
      |> send_notification(counter_currency)
    end
  end

  # Private functions

  defp send_notification({notification, price_difference, project}, counter_currency) do
    if Config.get(:slack_notifications_enabled) do
      send_slack_notification(price_difference, project, counter_currency)
    end

    Repo.insert!(notification)
  end

  defp send_notification(_, _), do: false

  defp send_slack_notification(price_difference, project, counter_currency) do
    %{status: 200} =
      http_client().post(
        Config.get(:webhook_url),
        notification_payload(price_difference, project, counter_currency),
        headers: %{"Content-Type" => "application/json"}
      )
  end

  defp fetch_price_points(%Project{ticker: ticker, coinmarketcap_id: cmc_id} = project) do
    ticker_cmc_id = ticker <> "_" <> cmc_id

    Store.fetch_price_points!(
      ticker_cmc_id,
      minutes_ago(@check_interval_minutes),
      DateTime.utc_now()
    )
  end

  defp notification_payload(
         price_difference,
         %Project{name: name, coinmarketcap_id: coinmarketcap_id},
         counter_currency
       ) do
    Poison.encode!(%{
      text:
        "#{name}: #{notification_emoji(price_difference)} #{Float.round(price_difference, 2)}% #{
          String.upcase(counter_currency)
        } in last hour. <https://coinmarketcap.com/currencies/#{coinmarketcap_id}/|price graph>",
      channel: notification_channel(counter_currency)
    })
  end

  defp notification_channel("btc") do
    Config.get(:notification_channel)
    |> Kernel.<>("-btc")
  end

  defp notification_channel(_) do
    Config.get(:notification_channel)
  end

  defp notification_emoji(price_difference) when price_difference > 0, do: ":signal_up:"
  defp notification_emoji(price_difference) when price_difference < 0, do: ":signal_down:"
end
