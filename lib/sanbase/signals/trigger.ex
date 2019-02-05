defprotocol Sanbase.Signals.Triggerable do
  def evaluate(trigger)

  @spec triggered?(struct()) :: boolean()
  def triggered?(trigger)

  @spec cache_key(struct()) :: String.t()
  def cache_key(trigger)
end

defmodule Sanbase.Signals.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  embedded_schema do
    field(:settings, :map)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :naive_datetime)
    field(:cooldown, :integer)
  end

  @doc false
  def changeset(schema, params) do
    schema
    |> cast(params, [:settings, :is_public, :cooldown, :last_triggered])
  end

  def evaluate(%Trigger{settings: trigger_settings} = trigger) do
    trigger_settings = Sanbase.Signals.Triggerable.evaluate(trigger_settings)
    %Trigger{trigger | settings: trigger_settings}
  end

  def triggered?(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Triggerable.triggered?(trigger_settings)
  end

  def cache_key(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Triggerable.cache_key(trigger_settings)
  end

  def has_cooldown?(%Trigger{last_triggered: nil}), do: false
  def has_cooldown?(%Trigger{cooldown: nil}), do: false

  def has_cooldown?(%Trigger{cooldown: cd, last_triggered: %DateTime{} = lt}) do
    Timex.compare(
      Timex.shift(lt, minutes: cd),
      Timex.now()
    ) == 1
  end
end
