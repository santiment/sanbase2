defmodule Sanbase.Repo.Migrations.DeletePriceVolumeDiffAlerts do
  use Ecto.Migration

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery, only: [trigger_type_is: 1]

  def up do
    from(ut in Sanbase.Alert.UserTrigger,
      where: trigger_type_is("price_volume_difference")
    )
    |> Sanbase.Repo.delete_all()
  end

  def down do
    :ok
  end
end
