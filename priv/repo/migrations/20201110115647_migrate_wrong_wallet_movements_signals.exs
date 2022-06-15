defmodule Sanbase.Repo.Migrations.MigrateWrongWalletMovementsAlerts do
  use Ecto.Migration

  alias Sanbase.Alert.Trigger.WalletTriggerSettings
  alias Sanbase.Alert.UserTrigger

  def up do
    setup()
    migrate_wallet_movement_signals()
  end

  def down do
    :ok
  end

  defp migrate_wallet_movement_signals() do
    WalletTriggerSettings.type()
    |> UserTrigger.get_all_triggers_by_type()
    |> Enum.each(&maybe_update/1)
  end

  defp maybe_update(
         %{
           trigger: %{
             settings:
               %{
                 selector: %{currency: currency, infrastructure: infr}
               } = settings
           }
         } = user_trigger
       )
       when infr != "XRP" do
    new_settings = %{settings | selector: %{slug: currency, infrastructure: infr}}

    {:ok, _} =
      UserTrigger.update_user_trigger(user_trigger.user.id, %{
        id: user_trigger.id,
        settings: new_settings
      })
  end

  defp maybe_update(
         %{
           trigger: %{
             settings:
               %{
                 selector: %{infrastructure: "Own"}
               } = settings
           }
         } = user_trigger
       ) do
    new_settings = %{settings | selector: %{infrastructure: ETH}}

    {:ok, _} =
      UserTrigger.update_user_trigger(user_trigger.user.id, %{
        id: user_trigger.id,
        settings: new_settings
      })
  end

  defp maybe_update(_), do: :ok

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
