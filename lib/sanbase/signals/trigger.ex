defmodule Sanbase.Signals.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:trigger, :map)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :naive_datetime)
    # cooldown in seconds
    field(:cooldown, :integer)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [:trigger, :is_public, :cooldown, :last_triggered])
    |> validate_required([:trigger])
  end
end
