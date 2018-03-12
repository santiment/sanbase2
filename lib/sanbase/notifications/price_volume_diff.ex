defmodule Sanbase.Notifications.PriceVolumeDiff do
  alias Sanbase.Model.Project
  alias Sanbase.InternalServices.TechIndicators
  alias Sanbase.Utils.Config
  alias Sanbase.Notifications.Utils

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  require Sanbase.Utils.Config

  @http_service Mockery.of("HTTPoison")

  @notification_type_name "price_volume_diff"

  @approximation_window 14
  @comparison_window 7

  def exec(project, currency) do
    currency = String.upcase(currency)

    if notifications_enabled?() &&
         not Utils.recent_notification?(
           project,
           seconds_ago(notifications_cooldown()),
           notification_type_name(currency)
         ) do
      {indicator, debug_info} = get_indicator(project.ticker, currency)

      if check_notification(indicator) do
        send_notification(project, currency, indicator, debug_info)
      end
    end
  end

  defp get_indicator(ticker, currency) do
    %{from_datetime: from_datetime, to_datetime: to_datetime} = get_calculation_interval()

    indicator =
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

    debug_info =
      debug_info(
        ticker,
        currency,
        from_datetime,
        to_datetime,
        "1d",
        @approximation_window,
        @comparison_window
      )

    {indicator, debug_info}
  end

  defp check_notification(%{price_volume_diff: price_volume_diff}) do
    Decimal.cmp(price_volume_diff, notification_threshold())
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

  defp send_notification(project, currency, indicator, debug_info) do
    {:ok, %HTTPoison.Response{status_code: 204}} =
      @http_service.post(
        webhook_url(),
        notification_payload(project, currency, indicator, debug_info),
        [
          {"Content-Type", "application/json"}
        ]
      )

    Utils.insert_notification(project, notification_type_name(currency))
  end

  defp notification_payload(
         %Project{name: name, ticker: ticker, coinmarketcap_id: coinmarketcap_id},
         currency,
         %{price_change: price_change, volume_change: volume_change},
         debug_info
       ) do
    Poison.encode!(%{
      content:
        "#{name}: #{ticker}/#{String.upcase(currency)} #{notification_emoji(price_change)} Price #{
          notification_emoji(volume_change)
        } Volume opposite trends. https://coinmarketcap.com/currencies/#{coinmarketcap_id} #{
          debug_info
        }",
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

  def debug_info(
        ticker,
        currency,
        from_datetime,
        to_datetime,
        aggregate_interval,
        approximation_window,
        comparison_window
      ) do
    case debug_url() do
      nil ->
        nil

      debug_url ->
        from_unix = DateTime.to_unix(from_datetime)
        to_unix = DateTime.to_unix(to_datetime)

        debug_url =
          "#{debug_url}?ticker=#{ticker}&currency=#{currency}&from_timestamp=#{from_unix}&to_timestamp=#{
            to_unix
          }&aggregate_interval=#{aggregate_interval}&approximation_window=#{approximation_window}&comparison_window=#{
            comparison_window
          }"

        "[DEBUG INFO: #{debug_url}]"
    end
  end

  defp nil_to_zero(nil), do: Decimal.new(0)
  defp nil_to_zero(value), do: value

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp notification_threshold() do
    Config.get(:notification_threshold)
    |> Decimal.new()
  end

  defp notifications_cooldown() do
    {res, _} =
      Config.get(:notifications_cooldown)
      |> Integer.parse()

    res
  end

  defp debug_url() do
    Config.get(:debug_url)
  end

  defp notifications_enabled?() do
    Config.get(:notifications_enabled)
  end
end
