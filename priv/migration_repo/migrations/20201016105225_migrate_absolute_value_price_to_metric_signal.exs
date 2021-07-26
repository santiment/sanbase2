defmodule Sanbase.Repo.Migrations.MigrateAbsoluteValuePriceToMetricAlert do
  use Ecto.Migration

  alias Sanbase.Alert.Trigger.{
    PricePercentChangeSettings,
    PriceAbsoluteChangeSettings,
    MetricTriggerSettings
  }

  alias Sanbase.Alert.UserTrigger

  def up do
    setup()
    migrate_price_amount_change_signals()
  end

  def down do
    :ok
  end

  defp migrate_price_amount_change_signals() do
    PriceAbsoluteChangeSettings.type()
    |> UserTrigger.get_all_triggers_by_type()
    |> Enum.each(fn user_trigger ->
      %{trigger: %{settings: settings}} = user_trigger

      {:ok, _} =
        UserTrigger.update_user_trigger(user_trigger.user, %{
          id: user_trigger.id,
          settings: %{
            type: MetricTriggerSettings.type(),
            metric: "price_usd",
            target: settings.target,
            channel: settings.channel,
            operation: settings.operation
          }
        })
    end)
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
