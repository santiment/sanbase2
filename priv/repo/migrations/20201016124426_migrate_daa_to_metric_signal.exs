defmodule Sanbase.Repo.Migrations.MigrateDaaToMetricAlert do
  use Ecto.Migration

  alias Sanbase.Alert.Trigger.{
    DailyActiveAddressesSettings,
    MetricTriggerSettings
  }

  alias Sanbase.Alert.UserTrigger

  def up do
    setup()
    migrate_daa_signals()
  end

  def down do
    :ok
  end

  defp migrate_daa_signals() do
    DailyActiveAddressesSettings.type()
    |> UserTrigger.get_all_triggers_by_type()
    |> Enum.each(fn user_trigger ->
      %{trigger: %{settings: settings}} = user_trigger

      {:ok, _} =
        UserTrigger.update_user_trigger(user_trigger.user.id, %{
          id: user_trigger.id,
          settings: %{
            type: MetricTriggerSettings.type(),
            metric: "active_addresses_24h",
            target: settings.target,
            channel: settings.channel,
            time_window: settings.time_window,
            operation: settings.operation
          }
        })
    end)
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
