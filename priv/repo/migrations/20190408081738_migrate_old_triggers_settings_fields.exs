defmodule Sanbase.Repo.Migrations.MigrateOldTriggersSettingsFields do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query
  import Sanbase.Alert.TriggerQuery

  alias Sanbase.Alert.Trigger.PriceAbsoluteChangeSettings
  alias Sanbase.Alert.Trigger.PricePercentChangeSettings
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Repo

  def up do
    run()
  end

  def down, do: :ok

  defp run do
    [PricePercentChangeSettings.type(), PriceAbsoluteChangeSettings.type()]
    |> Enum.flat_map(&get_triggers_by_type/1)
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

  defp merge_operation(%{"above" => above} = settings) do
    settings
    |> Map.put("operation", %{"above" => above})
    |> Map.drop(["above", "below"])
  end

  defp merge_operation(%{"percent_threshold" => percent_threshold} = settings) do
    settings
    |> Map.put("operation", %{"percent_up" => percent_threshold})
    |> Map.delete("percent_threshold")
  end

  defp merge_target(%{"target" => target} = settings) when is_binary(target) do
    Map.put(settings, "target", %{"slug" => target})
  end

  defp merge_target(target), do: target

  defp get_triggers_by_type(type) do
    Repo.all(from(ut in UserTrigger, where: trigger_type_equals?(type), preload: [:user]))
  end
end
