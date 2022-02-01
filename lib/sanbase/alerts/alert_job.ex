defmodule Sanbase.Alert.Job do
  @days 30

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery, only: [trigger_is_not_frozen: 0]

  alias Sanbase.Alert.UserTrigger

  def freeze_alerts() do
    get_alerts()
    |> Enum.chunk_every(300)
    |> Enum.each(fn alerts_chunk ->
      freeze_alerts(alerts_chunk)
    end)
  end

  defp get_alerts() do
    {:ok, user_ids_mapset} = Sanbase.Billing.get_sanbase_pro_user_ids()

    user_ids = Enum.to_list(user_ids_mapset)

    from(ut in UserTrigger,
      where:
        ut.inserted_at <= ago(@days, "day") and trigger_is_not_frozen() and
          ut.user_id not in ^user_ids
    )
    |> Sanbase.Repo.all()
  end

  defp freeze_alerts(alerts) do
    multi_update_result =
      alerts
      |> Enum.reduce(Ecto.Multi.new(), fn alert, multi ->
        changeset = UserTrigger.update_changeset(alert, %{trigger: %{is_frozen: true}})
        Ecto.Multi.update(multi, alert.id, changeset)
      end)
      |> Sanbase.Repo.transaction()

    case multi_update_result do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end
end
