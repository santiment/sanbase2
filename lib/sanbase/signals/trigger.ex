defmodule Sanbase.Signals.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:trigger, :map)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [:id, :trigger])
  end
end
