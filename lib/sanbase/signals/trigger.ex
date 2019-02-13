defprotocol Sanbase.Signals.Settings do
  def evaluate(trigger)

  @spec triggered?(struct()) :: boolean()
  def triggered?(trigger)

  @spec cache_key(struct()) :: String.t()
  def cache_key(trigger)
end

defmodule Sanbase.Signals.Trigger do
  @moduledoc ~s"""
  Module that represents an embedded schema that is used in UserTrigger`s `jsonb`
  column. It represents a trigger, providing some common fields:
    - `is_public` - boolean, indicating if other people can see that trigger
    - `last_triggered` - the last datetime when it was triggered
    - `cooldown` - after how long the trigger can be triggered and sent again.
    - `settings` field is a map that gets converted to one of the available
  TriggerSettings modules. They implement a protocol that allows the evaluator
  to easily process them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Model.Project

  embedded_schema do
    field(:settings, :map)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :map, default: %{})
    field(:cooldown, :string, default: "24h")
  end

  @doc false
  def changeset(schema, params) do
    schema
    |> cast(params, [:settings, :is_public, :cooldown, :last_triggered])
    |> validate_required([:settings, :is_public, :cooldown])
  end

  def evaluate(%Trigger{settings: %{target: target} = trigger_settings} = trigger) do
    trigger_settings =
      %{trigger_settings | filtered_target_list: remove_targets_on_cooldown(target, trigger)}
      |> Sanbase.Signals.Settings.evaluate()

    %Trigger{trigger | settings: trigger_settings}
  end

  def evaluate(%Trigger{settings: trigger_settings} = trigger) do
    trigger_settings = trigger_settings |> Sanbase.Signals.Settings.evaluate()
    %Trigger{trigger | settings: trigger_settings}
  end

  def triggered?(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.triggered?(trigger_settings)
  end

  def cache_key(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.cache_key(trigger_settings)
  end

  def has_cooldown?(%Trigger{last_triggered: lt}, _target) when lt == %{}, do: false

  def has_cooldown?(%Trigger{cooldown: cd, last_triggered: lt}, target) when is_map(lt) do
    case Map.get(lt, target) do
      nil ->
        false

      target_last_triggered ->
        target_last_triggered = target_last_triggered |> Sanbase.DateTimeUtils.from_iso8601!()

        Timex.compare(
          Timex.shift(target_last_triggered,
            seconds: Sanbase.DateTimeUtils.compound_duration_to_seconds(cd)
          ),
          Timex.now()
        ) == 1
    end
  end

  def set_last_triggered(
        %Trigger{last_triggered: lt} = trigger,
        target,
        datetime \\ DateTime.utc_now()
      )
      when is_binary(target) do
    %Trigger{
      trigger
      | last_triggered: Map.put(lt, target, datetime)
    }
  end

  defp remove_targets_on_cooldown(target, trigger)
       when is_binary(target) do
    remove_targets_on_cooldown([target], trigger)
  end

  defp remove_targets_on_cooldown(%{user_list: user_list_id}, trigger) do
    %{list_items: list_items} = Sanbase.UserLists.UserList.by_id(user_list_id)

    list_items
    |> Enum.map(fn %{project_id: id} -> id end)
    |> Project.List.slugs_by_ids()
    |> remove_targets_on_cooldown(trigger)
  end

  defp remove_targets_on_cooldown(target_list, trigger) when is_list(target_list) do
    target_list
    |> Enum.reject(&Sanbase.Signals.Trigger.has_cooldown?(trigger, &1))
  end
end
