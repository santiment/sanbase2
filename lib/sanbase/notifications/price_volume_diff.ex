defmodule Sanbase.Notifications.PriceVolumeDiff do
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro

  alias Sanbase.Prices
  alias Sanbase.Model.Project
  alias Sanbase.TechIndicators
  alias Sanbase.Notifications.{Notification, Type}

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)

  @doc ~s"""
  A notification is triggered when a price is increasing and the volume is decreasing.
  Currently we have only `USD` volume so we support only `USD` notification
  """
  def exec(project, "USD" = currency) do
    currency = String.upcase(currency)

    notification_type = Type.get_or_create("price_volume_diff")

    if Config.get(:notifications_enabled) &&
         not Notification.has_cooldown?(
           project,
           notification_type,
           notifications_cooldown()
         ) do
      with {from_datetime, to_datetime} <- get_calculation_interval(),
           true <- volume_over_threshold?(project, currency, from_datetime, to_datetime),
           {indicator, notification_log} <-
             get_indicator(project, currency, from_datetime, to_datetime),
           true <- check_notification(indicator) do
        send_notification(project, notification_type, currency, indicator, notification_log)
      end
    end
  end

  # Private functions

  # Calculate the notification only if the 24h volume is over some threshold ($100,000 by default)
  defp volume_over_threshold?(
         %Project{} = project,
         _currency,
         from_datetime,
         to_datetime
       ) do
    measurement = Sanbase.Influxdb.Measurement.name_from(project)

    case Prices.Store.fetch_average_volume(measurement, from_datetime, to_datetime) do
      {:ok, [[_dt, volume]]} ->
        volume >= notification_volume_threshold()

      _ ->
        false
    end
  end

  defp get_indicator(
         %Project{} = project,
         currency,
         from_datetime,
         to_datetime
       ) do
    indicator =
      TechIndicators.PriceVolumeDifference.price_volume_diff(
        project,
        currency,
        from_datetime,
        to_datetime,
        "1d",
        window_type(),
        approximation_window(),
        comparison_window(),
        1
      )
      |> case do
        {:ok,
         [
           %{
             datetime: datetime,
             price_volume_diff: price_volume_diff,
             price_change: price_change,
             volume_change: volume_change
           }
         ]} ->
          %{
            datetime: datetime,
            price_volume_diff: nil_to_zero(price_volume_diff),
            price_change: nil_to_zero(price_change),
            volume_change: nil_to_zero(volume_change)
          }

        _ ->
          %{
            datetime: to_datetime,
            price_volume_diff: 0,
            price_change: 0,
            volume_change: 0
          }
      end

    notification_log =
      get_notification_log(
        project,
        currency,
        from_datetime,
        to_datetime,
        "1d",
        window_type(),
        approximation_window(),
        comparison_window(),
        notification_threshold()
      )

    {indicator, notification_log}
  end

  defp check_notification(%{price_volume_diff: price_volume_diff}) do
    price_volume_diff >= notification_threshold()
  end

  defp get_calculation_interval() do
    to_datetime = DateTime.utc_now()

    from_datetime =
      Timex.shift(to_datetime, days: -approximation_window() - comparison_window() - 2)

    {from_datetime, to_datetime}
  end

  defp send_notification(
         project,
         notification_type,
         currency,
         indicator,
         {_notification_data, debug_info}
       ) do
    {:ok, %HTTPoison.Response{status_code: 204}} =
      http_client().post(
        webhook_url(),
        notification_payload(project, currency, indicator, debug_info),
        [
          {"Content-Type", "application/json"}
        ]
      )

    Notification.set_triggered(
      project,
      notification_type
    )
  end

  def notification_payload(
        %Project{name: name, ticker: ticker} = project,
        currency,
        %{datetime: datetime, price_change: price_change, volume_change: volume_change},
        debug_info
      ) do
    # Timex.shift(days: 1) is because the returned datetime is the beginning of the day
    {:ok, notification_date_string} =
      datetime
      |> Timex.shift(days: 1)
      |> Timex.format("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")

    Jason.encode!(%{
      content:
        "#{name}: #{ticker}/#{String.upcase(currency)} #{notification_emoji(price_change)} Price #{
          notification_emoji(volume_change)
        } Volume opposite trends (as of #{notification_date_string} UTC). #{
          Project.sanbase_link(project)
        } #{debug_info}",
      username: "Price-Volume Difference",
      embeds: notification_embeds(project)
    })
  end

  defp notification_embeds(project) do
    Sanbase.Chart.build_embedded_chart(
      project,
      Timex.shift(Timex.now(), days: -90),
      Timex.shift(Timex.now(), days: -1),
      chart_type: :volume
    )
  end

  defp notification_emoji(value) do
    cond do
      value < 0 -> ":small_red_triangle_down:"
      value > 0 -> ":small_red_triangle:"
      true -> " "
    end
  end

  defp get_notification_log(
         %Project{ticker: ticker, slug: slug},
         currency,
         from_datetime,
         to_datetime,
         aggregate_interval,
         window_type,
         approximation_window,
         comparison_window,
         notification_threshold
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    notification_data =
      "ticker_slug=#{ticker <> "_" <> slug}&currency=#{currency}&from_timestamp=#{from_unix}&to_timestamp=#{
        to_unix
      }&aggregate_interval=#{aggregate_interval}&window_type=#{window_type}&approximation_window=#{
        approximation_window
      }&comparison_window=#{comparison_window}&notification_threshold=#{notification_threshold}"

    debug_info =
      case Config.get(:debug_url) do
        nil ->
          nil

        debug_url ->
          debug_url = "#{debug_url}?#{notification_data}"

          "[DEBUG INFO: #{debug_url}]"
      end

    {notification_data, debug_info}
  end

  defp nil_to_zero(nil), do: 0
  defp nil_to_zero(value), do: value

  defp webhook_url(), do: Config.get(:webhook_url)

  defp window_type(), do: Config.get(:window_type)

  defp approximation_window() do
    {res, _} =
      Config.get(:approximation_window)
      |> Integer.parse()

    res
  end

  defp comparison_window() do
    {res, _} =
      Config.get(:comparison_window)
      |> Integer.parse()

    res
  end

  defp notification_threshold() do
    {res, _} =
      Config.get(:notification_threshold)
      |> Float.parse()

    res
  end

  defp notification_volume_threshold() do
    {res, _} =
      Config.get(:notification_volume_threshold)
      |> Integer.parse()

    res
  end

  defp notifications_cooldown() do
    {res, _} =
      Config.get(:notifications_cooldown)
      |> Integer.parse()

    res
  end
end
