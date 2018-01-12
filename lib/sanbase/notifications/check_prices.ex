defmodule Sanbase.Notifications.CheckPrices do
  use Tesla

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Notifications.CheckPrices.ComputeMovements
  alias Sanbase.Utils.Config

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  require Sanbase.Utils.Config

  @http_service Mockery.of("Tesla")

  @cooldown_period_in_sec 60 * 60 # 60 minutes
  @check_interval_in_sec 60 * 60 # 60 minutes
  @price_change_threshold 5 # percent

  def exec(project, counter_currency) do
    unless ComputeMovements.recent_notification?(project, seconds_ago(@cooldown_period_in_sec), counter_currency) do
      prices = fetch_price_points(project, counter_currency)

      ComputeMovements.build_notification(project, counter_currency, prices, @price_change_threshold)
      |> send_notification(counter_currency)
    end
  end

  defp fetch_price_points(project, counter_currency) do
    ticker = price_ticker(project, counter_currency)

    Store.fetch_price_points(ticker, seconds_ago(@check_interval_in_sec), DateTime.utc_now())
  end

  def send_notification({notification, price_difference, project}, counter_currency) do
    %{status: 200} = @http_service.post(
      Config.get(:webhook_url),
      notification_payload(price_difference, project, counter_currency),
      headers: %{"Content-Type" => "application/json"}
    )

    Repo.insert!(notification)
  end

  def send_notification(_, _), do: false

  defp price_ticker(%Project{ticker: ticker}, counter_currency) do
    "#{ticker}_#{String.upcase(counter_currency)}"
  end

  defp notification_payload(price_difference, %Project{name: name, coinmarketcap_id: coinmarketcap_id}, counter_currency) do
    Poison.encode!(%{
      text: "#{name}: #{notification_emoji(price_difference)} #{Float.round(price_difference, 2)}% #{String.upcase(counter_currency)} in last hour. <https://coinmarketcap.com/currencies/#{coinmarketcap_id}/|price graph>",
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
