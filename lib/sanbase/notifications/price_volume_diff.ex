defmodule Sanbase.Notifications.PriceVolumeDiff do
  alias Sanbase.Model.Project
  alias Sanbase.InternalServices.TechIndicators
  alias Sanbase.Utils.Config
  alias Sanbase.Notifications.Utils

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  require Sanbase.Utils.Config

  @http_service Mockery.of("HTTPoison")

  @notification_type_name "price_volume_diff"
  # roughly 3 months
  @calculation_interval_in_days 3 * 30
  # 60 minutes
  @cooldown_period_in_sec 60 * 60
  @price_volume_diff_threshold 0.1

  def exec(project, currency) do
    if notifications_enabled?() and
         not Utils.recent_notification?(
           project,
           seconds_ago(@cooldown_period_in_sec),
           notification_type_name(currency)
         ) do
      price_volume_diff = get_price_volume_diff(project.ticker, currency)

      if check_notification(price_volume_diff) do
        send_notification(project, currency, price_volume_diff)
      end
    end
  end

  defp get_price_volume_diff(ticker, currency) do
    %{from_datetime: from_datetime, to_datetime: to_datetime} = get_calculation_interval()

    TechIndicators.price_volume_diff(
      ticker,
      currency,
      from_datetime,
      to_datetime,
      "1d",
      1
    )
    |> case do
      {:ok, [%{price_volume_diff: nil}]} -> Decimal.new(0)
      {:ok, [%{price_volume_diff: price_volume_diff}]} -> price_volume_diff
      _ -> Decimal.new(0)
    end
  end

  defp check_notification(price_volume_diff) do
    Decimal.cmp(price_volume_diff, Decimal.new(@price_volume_diff_threshold))
    |> case do
      :lt -> false
      _ -> true
    end
  end

  defp notification_type_name(currency), do: @notification_type_name <> "_" <> currency

  defp get_calculation_interval() do
    to_datetime = DateTime.utc_now()
    from_datetime = Timex.shift(to_datetime, days: -@calculation_interval_in_days)

    %{from_datetime: from_datetime, to_datetime: to_datetime}
  end

  defp send_notification(project, currency, price_volume_diff) do
    {:ok, %HTTPoison.Response{status_code: 204}} =
      @http_service.post(
        webhook_url(),
        notification_payload(project, currency, price_volume_diff),
        [{"Content-Type", "application/json"}]
      )

    Utils.insert_notification(project, notification_type_name(currency))
  end

  defp notification_payload(
         %Project{name: name, coinmarketcap_id: coinmarketcap_id},
         currency,
         _price_volume_diff
       ) do
    Poison.encode!(%{
      content:
        "#{name}: price-volume difference in #{String.upcase(currency)}. https://coinmarketcap.com/currencies/#{
          coinmarketcap_id
        }",
      username: "Price-Volume Difference"
    })
  end

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp notifications_enabled?() do
    Config.get(:notifications_enabled)
  end
end
