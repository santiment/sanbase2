defprotocol Sanbase.Signals.Triggerable do
  @spec triggered?(struct()) :: boolean()
  def triggered?(trigger)
  @spec cache_key(struct()) :: String.t()
  def cache_key(trigger)
end

defmodule Sanbase.Signals.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:settings, :map)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :naive_datetime)
    field(:cooldown, :integer)
  end

  @spec changeset(
          {map(), map()} | %{:__struct__ => atom(), optional(atom()) => any()},
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def changeset(schema, params) do
    schema
    |> cast(params, [:settings, :is_public, :cooldown, :last_triggered])
  end

  def triggered?(trigger) do
    Sanbase.Signals.Triggerable.triggered?(trigger)
  end

  def cache_key(trigger) do
    Sanbase.Signals.Triggerable.cache_key(trigger)
  end

  defp has_cooldown?(%{last_triggered: nil}), do: false
  defp has_cooldown?(%{cooldown: nil}), do: false

  defp has_cooldown?(%{cooldown: cd, last_triggered: %DateTime{} = lt}) do
    Timex.compare(
      Timex.shift(lt, minutes: cd),
      Timex.now()
    ) == 1
  end
end
