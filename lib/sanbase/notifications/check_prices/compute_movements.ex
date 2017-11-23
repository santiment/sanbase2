defmodule Sanbase.Notifications.CheckPrices.ComputeMovements do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Type

  import Ecto.Query

  @notification_name "price_change"

  def recent_notification?(project, cooldown_datetime) do
    type_id = price_notification_type_id()

    recent_notification?(project, type_id, cooldown_datetime)
  end

  def build_notification(project, prices, change_threshold_percent) do
    type_id = price_notification_type_id()

    diff = price_difference(prices)

    if (Kernel.abs(diff) >= change_threshold_percent) do
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

  defp price_difference([]), do: 0

  defp price_difference(prices) do
    {[ts1, low_price | _], [ts2, high_price | _]} = Enum.min_max_by(prices, fn [_ts, price | _] -> price end)

    difference_sign(ts2, ts1) * (high_price - low_price) * 100 / low_price
  end

  defp recent_notification?(%Project{id: id}, type_id, cooldown_datetime) do
    Notification
    |> where([n], project_id: ^id, type_id: ^type_id)
    |> where([n], n.inserted_at > ^cooldown_datetime)
    |> Repo.aggregate(:count, :id)
    |> Kernel.>(0)
  end

  defp price_notification_type_id do
    type = Repo.get_by(Type, name: @notification_name) || Repo.insert!(%Type{name: @notification_name})

    type.id
  end

  defp difference_sign(high_ts, low_ts) do
    case DateTime.compare(high_ts, low_ts) do
      :gt -> 1
      :lt -> -1
      _ -> 0
    end
  end
end
