defmodule Sanbase.Alert.Job do
  @days 30

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery, only: [trigger_is_not_frozen: 0, trigger_is_frozen: 0]

  alias Sanbase.Alert.UserTrigger

  def freeze_alerts() do
    get_not_frozen_alerts()
    |> Enum.chunk_every(300)
    |> Enum.each(fn alerts_chunk ->
      update_is_frozen_field(alerts_chunk, _is_frozen = true)
    end)
  end

  def unfreeze_alerts() do
    get_frozen_alerts()
    |> Enum.chunk_every(300)
    |> Enum.each(fn alerts_chunk ->
      update_is_frozen_field(alerts_chunk, _is_frozen = false)
    end)
  end

  defp get_not_frozen_alerts() do
    # Do not freeze the existing alerts of users with sanbase subscriptions or the
    # alerts of @santiment.net users.
    {:ok, user_ids1} = Sanbase.Billing.get_sanbase_pro_user_ids()
    {:ok, user_ids2} = Sanbase.Accounts.Search.user_ids_with_santiment_email()

    user_ids = Enum.uniq(user_ids1 ++ user_ids2)

    from(ut in UserTrigger,
      where:
        ut.inserted_at <= ago(@days, "day") and trigger_is_not_frozen() and
          ut.user_id not in ^user_ids
    )
    |> Sanbase.Repo.all()
  end

  defp get_frozen_alerts() do
    # Unfreeze the alerts of users with sanbase subscriptions or with
    # @santiment.net email
    {:ok, user_ids1} = Sanbase.Billing.get_sanbase_pro_user_ids()
    {:ok, user_ids2} = Sanbase.Accounts.Search.user_ids_with_santiment_email()

    user_ids = Enum.uniq(user_ids1 ++ user_ids2)

    from(ut in UserTrigger,
      where: trigger_is_frozen() and ut.user_id in ^user_ids
    )
    |> Sanbase.Repo.all()
  end

  defp update_is_frozen_field(alerts, is_frozen) do
    multi_update_result =
      alerts
      |> Enum.reduce(Ecto.Multi.new(), fn alert, multi ->
        changeset = UserTrigger.update_changeset(alert, %{trigger: %{is_frozen: is_frozen}})
        Ecto.Multi.update(multi, alert.id, changeset)
      end)
      |> Sanbase.Repo.transaction()

    case multi_update_result do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end
end
