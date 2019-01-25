defmodule Sanbase.Signals.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:trigger, :map)
    field(:is_public, :boolean, default: false)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [:trigger])
    |> validate_required([:trigger])
  end
end
