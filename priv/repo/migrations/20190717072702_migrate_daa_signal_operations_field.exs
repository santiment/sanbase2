defmodule Sanbase.Repo.Migrations.MigrateDaaAlertOperationsField do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery

  alias Sanbase.Alert.Trigger.DailyActiveAddressesSettings
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Repo

  def up do
    run()
  end

  def down, do: :ok

  defp run do
    DailyActiveAddressesSettings.type()
    |> get_triggers_by_type()
    |> Enum.map(fn ut -> {ut.user, ut.id, ut.trigger.settings} end)
    |> Enum.map(fn {user, id, settings} ->
      {user, id, settings |> merge_operation() |> merge_target()}
    end)
    |> update_triggers()
  end

  defp update_triggers(triggers) do
    Enum.map(triggers, fn {user, id, settings} ->
      UserTrigger.update_user_trigger(user.id, %{id: id, settings: settings})
    end)
  end

  defp merge_operation(%{"percent_threshold" => percent_threshold} = settings) do
    settings
    |> Map.put("operation", %{"percent_up" => percent_threshold})
    |> Map.delete("percent_threshold")
  end

  defp merge_operation(operation), do: operation

  defp merge_target(%{"target" => target} = settings) when is_binary(target) do
    Map.put(settings, "target", %{"slug" => target})
  end

  defp merge_target(target), do: target

  defp get_triggers_by_type(type) do
    Repo.all(from(ut in UserTrigger, where: trigger_type_equals?(type), preload: [:user]))
  end
end
