defmodule Sanbase.Notifications.CheckPrices.ComputeMovements do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Type

  import Ecto.Query

  @notification_name "price_change"

  def recent_notification?(project, cooldown_datetime, counter_currency) do
    type_id = price_notification_type_id(counter_currency)

    recent_notifications_count(project, type_id, cooldown_datetime) > 0
  end

  def build_notification(project, counter_currency, prices, change_threshold_percent)
      when counter_currency in ["USD", "BTC"] do
    type_id = price_notification_type_id(counter_currency)

    diff = price_difference(prices, counter_currency)

    if Kernel.abs(diff) >= change_threshold_percent do
      {
        %Notification{
          project_id: project.id,
          type_id: type_id
        },
        diff,
        project
      }
    end
  end

  defp price_difference([], _), do: 0

  defp price_difference(prices, "USD") do
    {[ts1, low_price_usd | _], [ts2, high_price_usd | _]} =
      Enum.min_max_by(prices, fn [_ts, price | _] -> price end)

    difference_sign(ts2, ts1) * (high_price_usd - low_price_usd) * 100 / low_price_usd
  end

  defp price_difference(prices, "BTC") do
    {[ts1, _low_price_usd, low_price_btc | _], [ts2, _high_price_usd, high_price_btc | _]} =
      Enum.min_max_by(prices, fn [_ts, _price_usd, price_btc | _] -> price_btc end)

    difference_sign(ts2, ts1) * (high_price_btc - low_price_btc) * 100 / low_price_btc
  end

  defp recent_notifications_count(%Project{id: id}, type_id, cooldown_datetime) do
    Notification
    |> where([n], project_id: ^id, type_id: ^type_id)
    |> where([n], n.inserted_at > ^cooldown_datetime)
    |> Repo.aggregate(:count, :id)
  end

  defp price_notification_type_id(counter_currency) do
    name = notification_name(counter_currency)
    type = Repo.get_by(Type, name: name) || Repo.insert!(%Type{name: name})

    type.id
  end

  defp notification_name(counter_currency), do: @notification_name <> "_" <> counter_currency

  defp difference_sign(high_ts, low_ts) do
    case DateTime.compare(high_ts, low_ts) do
      :gt -> 1
      :lt -> -1
      _ -> 0
    end
  end
end
