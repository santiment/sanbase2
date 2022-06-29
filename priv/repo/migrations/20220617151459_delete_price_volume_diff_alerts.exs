defmodule Sanbase.Repo.Migrations.DeletePriceVolumeDiffAlerts do
  use Ecto.Migration

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery, only: [trigger_type_is: 1]

  def up do
    drop(
      constraint(:signals_historical_activity, :signals_historical_activity_user_trigger_id_fkey)
    )

    alter table(:signals_historical_activity) do
      modify(:user_trigger_id, references(:user_triggers, on_delete: :delete_all))
    end

    from(ut in Sanbase.Alert.UserTrigger,
      where: trigger_type_is("price_volume_difference")
    )
    |> Sanbase.Repo.delete_all()
  end

  def down do
    :ok
  end
end
