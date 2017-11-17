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

  def exec do
    ComputeMovements.projects_to_monitor(seconds_ago(@cooldown_period_in_sec))
    |> Enum.map(&fetch_price_points/1)
    |> ComputeMovements.compute_notifications(@price_change_threshold)
    |> Enum.map(&send_notification/1)
  end

  defp fetch_price_points(project) do
    {
      project,
      Store.fetch_price_points(price_ticker(project), seconds_ago(@check_interval_in_sec), DateTime.utc_now())
    }
  end

  def send_notification({notification, price_difference, project}) do
    %{status: 200} = @http_service.post(
      webhook_url(),
      notification_payload(price_difference, project),
      headers: %{"Content-Type" => "application/json"}
    )

    Repo.insert!(notification)
  end

  defp price_ticker(%Project{ticker: ticker}) do
    "#{ticker}_USD"
  end

  defp notification_payload(price_difference, %Project{name: name, coinmarketcap_id: coinmarketcap_id}) do
    Poison.encode!(%{
      text: "#{notification_emoji(price_difference)} #{name}: #{Float.round(price_difference, 2)}% change in last hour. <https://coinmarketcap.com/currencies/#{coinmarketcap_id}/|price graph>",
      channel: notification_channel(Mix.env)
    })
  end

  defp webhook_url() do
    Application.fetch_env!(:sanbase, SanBase.Notifications.CheckPrice)
    |> Keyword.get(:webhook_url)
    |> parse_webhook_url()
  end

  defp parse_webhook_url({:system, env_key}), do: System.get_env(env_key)

  defp parse_webhook_url(value), do: value

  defp notification_emoji(price_difference) when price_difference > 0, do: ":signal_up:"
  defp notification_emoji(price_difference) when price_difference < 0, do: ":signal_down:"

  defp notification_channel(:prod), do: "#signals"
  defp notification_channel(_), do: "#signals-stage"
end
