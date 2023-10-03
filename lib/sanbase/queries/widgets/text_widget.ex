defmodule Sanbase.Queries.TextWidget do
  @moduledoc ~s"""
  TODO
  """
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field(:name, :string)
    field(:description, :string)
    field(:body, :string)

    timestamps()
  end

  @fields [
    :name,
    :description,
    :body
  ]

  def changeset(%__MODULE__{} = plan, attrs) do
    plan
    |> cast(attrs, @fields)
  end

  def new(args) do
    %__MODULE__{}
    |> changeset(args)
  end
end
