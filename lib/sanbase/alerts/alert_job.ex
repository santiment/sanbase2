defmodule Sanbase.Alert.Job do
  @days 0

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery, only: [trigger_is_not_frozen: 0]

  alias Sanbase.Alert.UserTrigger

  def freeze_alerts() do
    alerts =
      from(ut in UserTrigger,
        where: ut.inserted_at >= ago(@days, "day") and trigger_is_not_frozen()
      )
      |> Sanbase.Repo.all()

    alerts
    |> Enum.map(fn alert ->
      UserTrigger.update_changeset(alert, %{trigger: %{is_frozen: true}})
    end)
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        Ecto.Multi.update(multi, offset, changeset)
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, _} ->
        :ok

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end
end
