defmodule Sanbase.Notifications.CheckPrices do
  use Tesla

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Notifications.CheckPrices.ComputeMovements

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  @http_service Mockery.of("Tesla")

  @cooldown_period_in_sec 60 * 60 # 60 minutes
  @check_interval_in_sec 60 * 60 # 60 minutes
  @price_change_threshold 5 # percent

  def exec(project) do
    unless ComputeMovements.recent_notification?(project, seconds_ago(@cooldown_period_in_sec)) do
      prices = fetch_price_points(project)

      ComputeMovements.build_notification(project, prices, @price_change_threshold)
      |> send_notification()
    end
  end

  defp fetch_price_points(project) do
    Store.fetch_price_points(price_ticker(project), seconds_ago(@check_interval_in_sec), DateTime.utc_now())
  end

  def send_notification({notification, price_difference, project}) do
    %{status: 200} = @http_service.post(
      webhook_url(),
      notification_payload(price_difference, project),
      headers: %{"Content-Type" => "application/json"}
    )

    Repo.insert!(notification)
  end

  def send_notification(_), do: false

  defp price_ticker(%Project{ticker: ticker}) do
    "#{ticker}_USD"
  end

  defp notification_payload(price_difference, %Project{name: name, coinmarketcap_id: coinmarketcap_id}) do
    Poison.encode!(%{
      text: "#{name}: #{notification_emoji(price_difference)} #{Float.round(price_difference, 2)}% in last hour. <https://coinmarketcap.com/currencies/#{coinmarketcap_id}/|price graph>",
      channel: notification_channel()
    })
  end

  defp webhook_url() do
    Application.fetch_env!(:sanbase, Sanbase.Notifications.CheckPrice)
    |> Keyword.get(:webhook_url)
    |> parse_config_value()
  end

  defp notification_channel() do
    Application.fetch_env!(:sanbase, Sanbase.Notifications.CheckPrice)
    |> Keyword.get(:notification_channel)
    |> parse_config_value()
  end

  defp parse_config_value({:system, env_key, default}), do: System.get_env(env_key) || default
  defp parse_config_value({:system, env_key}), do: System.get_env(env_key)

  defp parse_config_value(value), do: value

  defp notification_emoji(price_difference) when price_difference > 0, do: ":signal_up:"
  defp notification_emoji(price_difference) when price_difference < 0, do: ":signal_down:"

end
