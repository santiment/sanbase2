defmodule Migrate do
  import Ecto.Query
  import Sanbase.Signals.TriggerQuery

  alias Sanbase.Signals.UserTrigger

  alias Sanbase.Signals.Trigger.{
    PricePercentChangeSettings,
    PriceAbsoluteChangeSettings
  }

  alias Sanbase.Repo

  def run() do
    [PricePercentChangeSettings.type(), PriceAbsoluteChangeSettings.type()]
    |> Enum.flat_map(&get_triggers_by_type/1)
    |> Enum.map(fn ut -> {ut.user, ut.id, ut.trigger.settings} end)
    |> Enum.map(fn {user, id, settings} ->
      {user, id, settings |> merge_operation() |> merge_target()}
    end)
    |> update_triggers()
  end

  defp update_triggers(triggers) do
    triggers
    |> Enum.map(fn {user, id, settings} ->
      UserTrigger.update_user_trigger(user, %{id: id, settings: settings})
    end)
  end

  defp merge_operation(%{"above" => above} = settings) do
    settings
    |> Map.merge(%{
      "operation" => %{"above" => above}
    })
    |> Map.drop(["above", "below"])
  end

  defp merge_operation(%{"percent_threshold" => percent_threshold} = settings) do
    settings
    |> Map.merge(%{
      "operation" => %{"percent_up" => percent_threshold}
    })
    |> Map.drop(["percent_threshold"])
  end

  defp merge_target(%{"target" => target} = settings) when is_binary(target) do
    settings
    |> Map.merge(%{
      "target" => %{"slug" => target}
    })
  end

  defp merge_target(target), do: target

  defp get_triggers_by_type(type) do
    from(
      ut in UserTrigger,
      where: trigger_type_is(type),
      preload: [:user]
    )
    |> Repo.all()
  end
end
