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

  embedded_schema do
    field(:settings, :map)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :naive_datetime)
    field(:cooldown, :string)
  end

  @doc false
  def changeset(schema, params) do
    schema
    |> cast(params, [:settings, :is_public, :cooldown, :last_triggered])
  end

  def evaluate(%Trigger{settings: trigger_settings} = trigger) do
    trigger_settings = Sanbase.Signals.Settings.evaluate(trigger_settings)
    %Trigger{trigger | settings: trigger_settings}
  end

  def triggered?(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.triggered?(trigger_settings)
  end

  def cache_key(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.cache_key(trigger_settings)
  end

  def has_cooldown?(%Trigger{last_triggered: nil}), do: false
  def has_cooldown?(%Trigger{cooldown: nil}), do: false

  def has_cooldown?(%Trigger{cooldown: cd, last_triggered: lt}) do
    Timex.compare(
      Timex.shift(lt, seconds: Sanbase.DateTimeUtils.compound_duration_to_seconds(cd)),
      Timex.now()
    ) == 1
  end
end
