defmodule Sanbase.Notifications.CheckPrices.ComputeMovements do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Type

  import Ecto.Query

  @notification_name "price_change"

  def projects_to_monitor(cooldown_datetime) do
    type_id = price_notification_type_id()

    Project
    |> where([p], not is_nil(p.ticker) and not is_nil(p.coinmarketcap_id))
    |> Repo.all()
    |> Enum.reject(&recent_notification?(&1, type_id, cooldown_datetime))
  end

  def compute_notifications(projects_with_prices, change_threshold_percent) do
    type_id = price_notification_type_id()

    projects_with_prices
    |> Enum.map(&price_difference/1)
    |> Enum.filter(fn {_project, price_difference} ->
      Kernel.abs(price_difference) >= change_threshold_percent
    end)
    |> Enum.map(&build_notification(&1, type_id))
  end

  defp price_difference({project, []}), do: {project, 0}

  defp price_difference({project, prices}) do
    {[ts1, low_price | _], [ts2, high_price | _]} = Enum.min_max_by(prices, fn [_ts, price | _] -> price end)

    {project, difference_sign(ts2, ts1) * (high_price - low_price) * 100 / low_price}
  end

  defp build_notification({%Project{id: id} = project, price_difference}, type_id) do
    {
      %Notification{
        project_id: id,
        type_id: type_id
      },
      price_difference,
      project
    }
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
