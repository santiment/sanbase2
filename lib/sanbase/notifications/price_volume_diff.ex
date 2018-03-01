defmodule Sanbase.Notifications.PriceVolumeDiff do
  alias Sanbase.Model.Project
  alias Sanbase.InternalServices.TechIndicators
  alias Sanbase.Utils.Config
  alias Sanbase.Notifications.Utils

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  require Sanbase.Utils.Config

  @http_service Mockery.of("HTTPoison")

  @notification_type_name "price_volume_diff"
  # 60 minutes
  @cooldown_period_in_sec 60 * 60

  @approximation_window 14
  @comparison_window 7
  @price_volume_diff_threshold 0.1

  def exec(project, currency) do
    currency = String.upcase(currency)

    if notifications_enabled?() &&
         not Utils.recent_notification?(
           project,
           seconds_ago(@cooldown_period_in_sec),
           notification_type_name(currency)
         ) do
      indicator = get_indicator(project.ticker, currency)

      if check_notification(indicator) do
        send_notification(project, currency, indicator)
      end
    end
  end

  defp get_indicator(ticker, currency) do
    %{from_datetime: from_datetime, to_datetime: to_datetime} = get_calculation_interval()

    TechIndicators.price_volume_diff_ma(
      ticker,
      currency,
      from_datetime,
      to_datetime,
      "1d",
      @approximation_window,
      @comparison_window,
      1
    )
    |> case do
      {:ok,
       [
         %{
           price_volume_diff: price_volume_diff,
           price_change: price_change,
           volume_change: volume_change
         }
       ]} ->
        %{
          price_volume_diff: nil_to_zero(price_volume_diff),
          price_change: nil_to_zero(price_change),
          volume_change: nil_to_zero(volume_change)
        }

      _ ->
        %{
          price_volume_diff: Decimal.new(0),
          price_change: Decimal.new(0),
          volume_change: Decimal.new(0)
        }
    end
  end

  defp check_notification(%{price_volume_diff: price_volume_diff}) do
    Decimal.cmp(price_volume_diff, Decimal.new(@price_volume_diff_threshold))
    |> case do
      :lt -> false
      _ -> true
    end
  end

  defp notification_type_name(currency), do: @notification_type_name <> "_" <> currency

  defp get_calculation_interval() do
    to_datetime = DateTime.utc_now()
    from_datetime = Timex.shift(to_datetime, days: -@approximation_window - @comparison_window)

    %{from_datetime: from_datetime, to_datetime: to_datetime}
  end

  defp send_notification(project, currency, indicator) do
    {:ok, %HTTPoison.Response{status_code: 204}} =
      @http_service.post(webhook_url(), notification_payload(project, currency, indicator), [
        {"Content-Type", "application/json"}
      ])

    Utils.insert_notification(project, notification_type_name(currency))
  end

  defp notification_payload(
         %Project{name: name, ticker: ticker, coinmarketcap_id: coinmarketcap_id},
         currency,
         %{price_change: price_change, volume_change: volume_change}
       ) do
    Poison.encode!(%{
      content:
        "#{name}: #{ticker}/#{String.upcase(currency)} #{notification_emoji(price_change)} Price #{
          notification_emoji(volume_change)
        } Volume. https://coinmarketcap.com/currencies/#{coinmarketcap_id}",
      username: "Price-Volume Difference"
    })
  end

  defp notification_emoji(value) do
    Decimal.cmp(value, Decimal.new(0))
    |> case do
      :lt -> ":small_red_triangle_down:"
      :gt -> ":small_red_triangle:"
      :eq -> " "
    end
  end

  defp nil_to_zero(nil), do: Decimal.new(0)
  defp nil_to_zero(value), do: value

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp notifications_enabled?() do
    Config.get(:notifications_enabled)
  end
end
